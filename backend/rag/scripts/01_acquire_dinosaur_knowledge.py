"""Acquire Wikipedia + OpenAlex into the dinosaur_knowledge SQL table.

Does not touch Azure Search — use 02_index_dinosaur_knowledge.py for that.

OpenAlex keeps up to OPENALEX_MAX_WORKS (default 10) unique papers per dinosaur:
already-stored works are skipped and gaps are topped up.

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

from sqlmodel import Session, select

from app.core.config import settings
from app.core.database import engine
from app.features.ingestion.models.dinosaur_knowledge import DinosaurKnowledge
from app.features.ingestion.public import parse_dino_names
from app.features.specimens.public import list_dinosaur_knowledge_subjects
from mesozoica_ai.common import (
    DEFAULT_SUBJECT_KIND,
    Document,
    JobSummary,
    RateLimitedError,
    needs_acquisition,
    sql_knowledge_overview,
    store_documents,
    subject_metadata,
    subject_query,
)
from mesozoica_ai.sources import retrieve_openalex, retrieve_wikipedia
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

    with Session(engine) as session:
        subjects = list_dinosaur_knowledge_subjects(session, names=dinos)
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
                    subject=subject,
                    summary=summary,
                    dry_run=dry_run,
                    overwrite=overwrite,
                    user_agent=user_agent,
                )
            if "openalex" in sources:
                try:
                    _acquire_openalex(
                        session,
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

        overview = sql_knowledge_overview(session, DinosaurKnowledge)
        for line in overview.log_lines(title="Overview (SQL dinosaur_knowledge)"):
            logger.info("%s", line)

    print(json.dumps(summary.model_dump(), indent=2, default=str))
    return summary.exit_code


def _acquire_wikipedia(
    session: Session,
    *,
    subject,
    summary: JobSummary,
    dry_run: bool,
    overwrite: bool,
    user_agent: str,
) -> None:
    label = f"{subject.name}/wikipedia"
    if dry_run:
        logger.info("%s: dry-run skip", label)
        summary.skipped += 1
        return
    if not needs_acquisition(
        session, DinosaurKnowledge, subject, "wikipedia", overwrite=overwrite
    ):
        logger.info("%s: already saved, skip", label)
        summary.skipped += 1
        return

    logger.info("%s: fetching", label)
    try:
        documents = retrieve_wikipedia(
            subject_query(subject, "wikipedia"),
            user_agent=user_agent,
            metadata=subject_metadata(subject, "wikipedia"),
        )
        outcome = store_documents(
            session,
            DinosaurKnowledge,
            subject=subject,
            source="wikipedia",
            documents=documents,
            overwrite=overwrite,
        )
        logger.info("%s: stored %s section(s) (%s)", label, len(documents), outcome)
    except Exception as exc:
        logger.exception("%s: failed (%s)", label, exc)
        outcome = store_documents(
            session,
            DinosaurKnowledge,
            subject=subject,
            source="wikipedia",
            error=exc,
            overwrite=overwrite,
        )
    summary.record(outcome)


def _acquire_openalex(
    session: Session,
    *,
    subject,
    summary: JobSummary,
    dry_run: bool,
    overwrite: bool,
    user_agent: str,
    paper_target: int,
) -> None:
    label = f"{subject.name}/openalex"
    row = session.exec(
        select(DinosaurKnowledge).where(
            DinosaurKnowledge.subject_kind == DEFAULT_SUBJECT_KIND,
            DinosaurKnowledge.subject_id == str(subject.id),
            DinosaurKnowledge.source == "openalex",
        )
    ).first()
    existing_docs = [] if overwrite or row is None else list(row.documents or [])
    have = paper_inventory(existing_docs)
    have_ids = {work_id for work_id, _ in have}

    if dry_run:
        logger.info("%s: dry-run (%s/%s papers)", label, len(have), paper_target)
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
            subject_query(subject, "openalex"),
            user_agent=user_agent,
            api_key=settings.openalex_api_key or "",
            limit=need,
            exclude_work_ids=have_ids,
            metadata=subject_metadata(subject, "openalex"),
        )
        if not new_documents:
            logger.warning(
                "%s: no new papers; still %s/%s", label, len(have), paper_target
            )
            summary.skipped += 1
            return
        _store_openalex_merge(
            session,
            subject=subject,
            summary=summary,
            label=label,
            existing_docs=existing_docs,
            new_documents=new_documents,
            paper_target=paper_target,
        )
    except RateLimitedError as exc:
        if exc.partial_documents:
            logger.warning(
                "%s: rate limited after partial fetch; saving %s new paper(s)",
                label,
                len(paper_inventory(exc.partial_documents)),
            )
            _store_openalex_merge(
                session,
                subject=subject,
                summary=summary,
                label=label,
                existing_docs=existing_docs,
                new_documents=list(exc.partial_documents),
                paper_target=paper_target,
            )
        raise
    except Exception as exc:
        logger.exception("%s: failed (%s)", label, exc)
        if have:
            logger.warning(
                "%s: top-up failed; keeping %s/%s", label, len(have), paper_target
            )
            summary.failed += 1
            return
        outcome = store_documents(
            session,
            DinosaurKnowledge,
            subject=subject,
            source="openalex",
            error=exc,
            overwrite=True,
        )
        summary.record(outcome)


def _store_openalex_merge(
    session: Session,
    *,
    subject,
    summary: JobSummary,
    label: str,
    existing_docs: list,
    new_documents: list,
    paper_target: int,
) -> None:
    merged = [
        *[Document.model_validate(item) for item in existing_docs],
        *new_documents,
    ]
    outcome = store_documents(
        session,
        DinosaurKnowledge,
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
