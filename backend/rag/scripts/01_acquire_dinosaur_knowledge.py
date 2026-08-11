"""Acquire Wikipedia revisions + OpenAlex into dinosaur_knowledge_source/doc.

Does not touch Azure Search — use 02_embed_dinosaur_knowledge.py then
03_ingest_dinosaur_knowledge.py for that.

Wikipedia text comes from the latest ``dinosaur_type_revision`` row (no live
Wikipedia fetch). OpenAlex keeps up to OPENALEX_MAX_WORKS (default 10) unique
papers per dinosaur: already-stored works are skipped and gaps are topped up.
When OpenAlex is enabled, dinosaurs never tried for OpenAlex are acquired
first, then partial sets are topped up toward the target. Dinosaurs already
tried with zero usable papers are recorded and skipped unless ``--overwrite``.

  cd backend
  .venv/bin/python rag/scripts/01_acquire_dinosaur_knowledge.py
  .venv/bin/python rag/scripts/01_acquire_dinosaur_knowledge.py --dinos Tyrannosaurus
  .venv/bin/python rag/scripts/01_acquire_dinosaur_knowledge.py --sources wikipedia --dry-run
"""

from __future__ import annotations

import argparse
import html
import json
import logging
import re
import sys
from pathlib import Path
from typing import Any

_BACKEND_ROOT = Path(__file__).resolve().parents[2]
if str(_BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(_BACKEND_ROOT))

from dotenv import load_dotenv

load_dotenv(_BACKEND_ROOT / ".env")
load_dotenv(_BACKEND_ROOT / "rag" / ".env")

logging.basicConfig(
    level=logging.INFO,
    format="%(levelname)s %(name)s: %(message)s",
)
for _noisy in ("httpx", "httpcore"):
    logging.getLogger(_noisy).setLevel(logging.WARNING)
logger = logging.getLogger("acquire")

from sqlmodel import Session

from app.core.config import settings
from app.core.database import engine
from app.features.ingestion.application.dinosaur_knowledge.repository import (
    dinosaur_knowledge_repo,
)
from app.features.ingestion.application.dinosaur_knowledge.wikipedia_documents import (
    wikipedia_documents_from_article,
)
from app.features.ingestion.public import parse_dino_names
from app.features.specimens.public import (
    get_latest_dinosaur_wikipedia_article,
    list_dinosaur_knowledge_subjects,
)
from mesozoica_ai.common import (
    Document,
    JobSummary,
    RateLimitedError,
    SourceFetchError,
    SqlModelKnowledgeRepository,
    log_knowledge_counts,
    needs_acquisition,
    store_documents,
    subject_metadata,
)
from mesozoica_ai.sources import retrieve_openalex
from mesozoica_ai.sources.openalex import paper_inventory


def run(
    *,
    dry_run: bool = False,
    overwrite: bool = False,
    dinos: list[str] | None = None,
    sources: list[str] | None = None,
    max_items: int | None = None,
) -> int:
    sources = sources or ["wikipedia", "openalex"]
    user_agent = settings.wikipedia_user_agent
    paper_target = settings.openalex_max_works
    if not dry_run and "openalex" in sources and not (settings.openalex_api_key or "").strip():
        raise RuntimeError("OPENALEX_API_KEY is required for OpenAlex acquisition")

    summary = JobSummary(candidates=0)
    interrupted = False
    with Session(engine) as session:
        repo = dinosaur_knowledge_repo(session)
        try:
            subjects = list_dinosaur_knowledge_subjects(session, names=dinos)
            if "openalex" in sources and not overwrite:
                subjects = _subjects_preferring_new_openalex(
                    repo, subjects, paper_target=paper_target
                )
            if max_items is not None:
                subjects = subjects[:max_items]
            logger.info(
                "Acquiring %s dinosaur(s) × sources=%s (dry_run=%s overwrite=%s openalex_target=%s)",
                len(subjects),
                ",".join(sources),
                dry_run,
                overwrite,
                paper_target,
            )

            summary = JobSummary(candidates=len(subjects) * len(sources))
            for subject in subjects:
                if "wikipedia" in sources:
                    _acquire_wikipedia(
                        session,
                        repo=repo,
                        subject=subject,
                        summary=summary,
                        dry_run=dry_run,
                        overwrite=overwrite,
                    )
                if "openalex" in sources:
                    try:
                        _acquire_openalex(
                            repo=repo,
                            subject=subject,
                            summary=summary,
                            dry_run=dry_run,
                            overwrite=overwrite,
                            user_agent=user_agent,
                            paper_target=paper_target,
                        )
                    except RateLimitedError as exc:
                        logger.warning(
                            "OpenAlex rate limited — stopping acquire early (%s)",
                            exc,
                        )
                        summary.failed += 1
                        break

            logger.info(
                "Done: succeeded=%s skipped=%s failed=%s",
                summary.succeeded,
                summary.skipped,
                summary.failed,
            )
        except KeyboardInterrupt:
            interrupted = True
            logger.warning("Interrupted")
        finally:
            log_knowledge_counts(logger, repo)

    print(json.dumps(summary.model_dump(), indent=2, default=str))
    return 130 if interrupted else summary.exit_code


def _openalex_state(
    repo: SqlModelKnowledgeRepository, subject
) -> tuple[Any | None, int]:
    row = repo.get_source(
        subject_kind="dinosaur",
        subject_id=str(subject.id),
        source="openalex",
    )
    if row is None:
        return None, 0
    return row, len(paper_inventory(repo.list_documents(row)))


def _subjects_preferring_new_openalex(
    repo: SqlModelKnowledgeRepository,
    subjects: list,
    *,
    paper_target: int,
) -> list:
    """Never-tried first, then partial top-ups, then tried-empty / complete."""
    never: list = []
    partial: list = []
    tried_empty: list = []
    complete: list = []
    for subject in subjects:
        row, count = _openalex_state(repo, subject)
        if row is None:
            never.append(subject)
        elif count >= paper_target:
            complete.append(subject)
        elif count == 0:
            tried_empty.append(subject)
        else:
            partial.append(subject)
    logger.info(
        "OpenAlex order: %s never tried, %s partial top-up, "
        "%s tried-empty, %s already at target",
        len(never),
        len(partial),
        len(tried_empty),
        len(complete),
    )
    return [*never, *partial, *tried_empty, *complete]


def _acquire_wikipedia(
    session: Session,
    *,
    repo: SqlModelKnowledgeRepository,
    subject,
    summary: JobSummary,
    dry_run: bool,
    overwrite: bool,
) -> None:
    label = f"{subject.name}/wikipedia"
    if dry_run:
        logger.info("%s: dry-run skip", label)
        summary.skipped += 1
        return
    if not needs_acquisition(repo, subject, "wikipedia", overwrite=overwrite):
        logger.info("%s: already saved, skip", label)
        summary.skipped += 1
        return

    logger.info("%s: loading latest dinosaur_type_revision", label)
    try:
        article = get_latest_dinosaur_wikipedia_article(
            session, dinosaur_type_id=int(subject.id)
        )
        if article is None:
            raise RuntimeError(
                f"No dinosaur_type_revision article for dinosaur_type_id={subject.id}"
            )
        source_version = (
            str(article.wikipedia_revision_id)
            if article.wikipedia_revision_id is not None
            else article.content_hash
        )
        documents = wikipedia_documents_from_article(
            article.article,
            title=article.wikipedia_title,
            page_id=article.wikipedia_page_id,
            source_version=source_version,
            published_at=article.article_date,
            metadata=subject_metadata(subject, "wikipedia"),
        )
        outcome = store_documents(
            repo,
            subject=subject,
            source="wikipedia",
            documents=documents,
            overwrite=overwrite,
        )
        logger.info(
            "%s: stored %s section(s) from revision %s (%s)",
            label,
            len(documents),
            article.revision_db_id,
            outcome,
        )
    except Exception as exc:
        logger.exception("%s: failed (%s)", label, exc)
        outcome = store_documents(
            repo,
            subject=subject,
            source="wikipedia",
            error=exc,
            overwrite=overwrite,
        )
    summary.record(outcome)


def _acquire_openalex(
    *,
    repo: SqlModelKnowledgeRepository,
    subject,
    summary: JobSummary,
    dry_run: bool,
    overwrite: bool,
    user_agent: str,
    paper_target: int,
) -> None:
    label = f"{subject.name}/openalex"
    row, _paper_count = _openalex_state(repo, subject)
    existing_docs = (
        [] if overwrite or row is None else repo.list_documents(row)
    )
    have = paper_inventory(existing_docs)
    have_ids = {work_id for work_id, _ in have}

    if dry_run:
        logger.info("%s: dry-run (%s/%s papers)", label, len(have), paper_target)
        summary.skipped += 1
        return

    if not overwrite and row is not None and len(have) == 0:
        logger.info("%s: skip (already tried, 0 papers)", label)
        summary.skipped += 1
        return

    if len(have) >= paper_target:
        logger.info("%s: skip (%s/%s papers)", label, len(have), paper_target)
        summary.skipped += 1
        return

    need = paper_target - len(have)
    logger.info("%s: %s/%s papers, need %s more", label, len(have), paper_target, need)
    if have:
        _log_papers(have)

    try:
        new_documents = retrieve_openalex(
            subject.name,
            user_agent=user_agent,
            api_key=settings.openalex_api_key or "",
            limit=need,
            exclude_work_ids=have_ids,
            metadata=subject_metadata(subject, "openalex"),
        )
    except RateLimitedError as exc:
        if exc.partial_documents:
            logger.warning(
                "%s: rate limited after partial fetch; saving %s new paper(s)",
                label,
                len(paper_inventory(exc.partial_documents)),
            )
            _store_openalex_merge(
                repo,
                subject=subject,
                summary=summary,
                label=label,
                existing_docs=existing_docs,
                new_documents=list(exc.partial_documents),
                paper_target=paper_target,
            )
        raise
    except Exception as exc:
        _record_openalex_failure(
            repo,
            subject=subject,
            summary=summary,
            label=label,
            have=have,
            error=exc,
        )
        return

    if not new_documents:
        if have:
            logger.info("%s: no new papers; still %s/%s", label, len(have), paper_target)
            summary.skipped += 1
            return
        logger.info("%s: no usable OpenAlex papers (recording empty try)", label)
        try:
            outcome = store_documents(
                repo,
                subject=subject,
                source="openalex",
                documents=[],
                overwrite=True,
            )
        except Exception as exc:
            _record_openalex_failure(
                repo,
                subject=subject,
                summary=summary,
                label=label,
                have=have,
                error=exc,
            )
            return
        summary.record(outcome)
        return

    try:
        _store_openalex_merge(
            repo,
            subject=subject,
            summary=summary,
            label=label,
            existing_docs=existing_docs,
            new_documents=new_documents,
            paper_target=paper_target,
        )
    except Exception as exc:
        _record_openalex_failure(
            repo,
            subject=subject,
            summary=summary,
            label=label,
            have=have,
            error=exc,
        )


def _record_openalex_failure(
    repo: SqlModelKnowledgeRepository,
    *,
    subject,
    summary: JobSummary,
    label: str,
    have: list[tuple[str, str]],
    error: BaseException,
) -> None:
    """Log without traceback for expected fetch misses; always keep the session usable."""
    repo.rollback()
    if isinstance(error, SourceFetchError):
        logger.warning("%s: %s", label, error)
    else:
        logger.exception("%s: failed (%s)", label, error)
    if have:
        logger.warning(
            "%s: top-up failed; keeping %s existing paper(s)", label, len(have)
        )
        summary.failed += 1
        return
    try:
        outcome = store_documents(
            repo,
            subject=subject,
            source="openalex",
            error=error,
            overwrite=True,
        )
    except Exception as store_exc:
        repo.rollback()
        logger.exception("%s: could not record failure (%s)", label, store_exc)
        summary.failed += 1
        return
    summary.record(outcome)


def _store_openalex_merge(
    repo: SqlModelKnowledgeRepository,
    *,
    subject,
    summary: JobSummary,
    label: str,
    existing_docs: list,
    new_documents: list,
    paper_target: int,
) -> None:
    merged = [
        *[
            item if isinstance(item, Document) else Document.model_validate(item)
            for item in existing_docs
        ],
        *new_documents,
    ]
    outcome = store_documents(
        repo,
        subject=subject,
        source="openalex",
        documents=merged,
        overwrite=True,
    )
    papers = paper_inventory(merged)
    added = paper_inventory(new_documents)
    logger.info(
        "%s: %s/%s papers (%s), added %s",
        label,
        len(papers),
        paper_target,
        outcome,
        len(added),
    )
    _log_papers(added)
    summary.record(outcome)


_TAG_RE = re.compile(r"<[^>]+>")


def _clean_title(title: str) -> str:
    return " ".join(_TAG_RE.sub("", html.unescape(title)).split())


def _log_papers(papers: list[tuple[str, str]]) -> None:
    for index, (work_id, title) in enumerate(papers, start=1):
        logger.info("  %2d. %s  %s", index, work_id, _clean_title(title))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dinos", nargs="+", default=None)
    parser.add_argument(
        "--sources", nargs="+", choices=("wikipedia", "openalex"), default=None
    )
    parser.add_argument("--max-items", type=int, default=None)
    parser.add_argument("--overwrite", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    raise SystemExit(
        run(
            dry_run=args.dry_run,
            overwrite=args.overwrite,
            dinos=parse_dino_names(args.dinos) if args.dinos else None,
            sources=args.sources,
            max_items=args.max_items,
        )
    )
