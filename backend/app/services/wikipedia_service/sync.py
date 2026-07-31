"""Orchestrate Wikipedia dinosaur sync into the database."""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone

from sqlmodel import Session, select

from app.core.config import settings
from app.models.dinosaur_type import DinosaurType
from app.models.dinosaur_type_revision import DinosaurTypeRevision
from app.services.wikipedia_service.category import (
    CategoryMember,
    default_wikipedia_dinosaur_categories,
    list_dinosaur_sync_batches,
)
from app.services.wikipedia_service.client import WikipediaClient
from app.services.wikipedia_service.content_hash import revision_content_hash
from app.services.wikipedia_service.metadata import fetch_page_metadata
from app.services.wikipedia_service.parser import parse_article_html

logger = logging.getLogger("wikipedia_sync")


@dataclass
class SyncCounters:
    types_added: int = 0
    revisions_appended: int = 0
    skipped: int = 0
    failed: int = 0
    disambiguation: int = 0


@dataclass
class SyncSummary:
    category: str
    total_candidates: int
    counters: SyncCounters = field(default_factory=SyncCounters)
    dry_run: bool = False
    elapsed_s: float = 0.0

    @property
    def failure_rate(self) -> float:
        attempted = (
            self.counters.types_added
            + self.counters.revisions_appended
            + self.counters.failed
        )
        if attempted == 0:
            return 0.0
        return self.counters.failed / attempted


def _is_stale(db_date: datetime | None, wiki_date: datetime) -> bool:
    if db_date is None:
        return True
    db_aware = db_date if db_date.tzinfo else db_date.replace(tzinfo=timezone.utc)
    wiki_aware = wiki_date if wiki_date.tzinfo else wiki_date.replace(tzinfo=timezone.utc)
    return wiki_aware > db_aware


def _is_incomplete(revision: DinosaurTypeRevision | None) -> bool:
    """True when a type has no usable current Wikipedia payload."""
    if revision is None:
        return True
    if not (revision.article or "").strip():
        return True
    if not revision.cladogram:
        return True
    return False


def _get_by_page_id(session: Session, page_id: int) -> DinosaurType | None:
    return session.exec(
        select(DinosaurType).where(DinosaurType.wikipedia_page_id == page_id)
    ).first()


def _find_existing(session: Session, *, page_id: int, title: str) -> DinosaurType | None:
    """Match by Wikipedia page id, then fall back to title for legacy stub rows."""
    by_page_id = _get_by_page_id(session, page_id)
    if by_page_id is not None:
        return by_page_id
    return session.exec(
        select(DinosaurType).where(DinosaurType.wikipedia_title == title)
    ).first()


def _current_revision(
    session: Session, dino_type: DinosaurType
) -> DinosaurTypeRevision | None:
    if dino_type.current_revision_id is None:
        return None
    return session.get(DinosaurTypeRevision, dino_type.current_revision_id)


def _build_revision(
    *,
    dinosaur_type_id: int,
    metadata,
    parsed,
) -> DinosaurTypeRevision:
    content_hash = revision_content_hash(
        article=parsed.article_html,
        long_description=parsed.long_description,
        birth=parsed.birth,
        death=parsed.death,
        period=parsed.period,
        diet_type=parsed.diet_type,
        cladogram=parsed.cladogram,
    )
    return DinosaurTypeRevision(
        dinosaur_type_id=dinosaur_type_id,
        article_date=metadata.article_date,
        content_hash=content_hash,
        birth=parsed.birth,
        death=parsed.death,
        period=parsed.period,
        cladogram=parsed.cladogram or {},
        diet_type=parsed.diet_type,
        long_description=parsed.long_description,
        article=parsed.article_html,
        llm_enriched=False,
    )


def sync_dinosaurs(
    session: Session,
    *,
    category: str | None = None,
    max_pages: int | None = None,
    dry_run: bool = False,
    overwrite: bool = False,
    dinos: list[str] | None = None,
    client: WikipediaClient | None = None,
) -> SyncSummary:
    """Sync dinosaur records from Wikipedia categories into the database."""
    categories = [category] if category else default_wikipedia_dinosaur_categories()
    cat = " + ".join(categories)
    cap = max_pages if max_pages is not None else settings.wikipedia_sync_max_pages
    start = time.monotonic()
    counters = SyncCounters()
    interrupted = False
    processed = 0

    own_client = client is None
    wiki = client or WikipediaClient()
    batches: list[tuple[str, list[CategoryMember]]] = []
    total = 0
    try:
        if dinos:
            batches = [
                (
                    "manual",
                    [CategoryMember(page_id=0, title=title) for title in dinos],
                )
            ]
        else:
            batches = list_dinosaur_sync_batches(wiki, category=category, max_pages=cap)

        total = sum(len(members) for _, members in batches)
        logger.info(
            "wikipedia_sync: starting categories=%s total_candidates=%d overwrite=%s dinos=%s",
            cat,
            total,
            overwrite,
            dinos,
        )

        try:
            processed = 0
            for batch_category, members in batches:
                batch_total = len(members)
                logger.info(
                    "wikipedia_sync: [%s] starting candidates=%d",
                    batch_category,
                    batch_total,
                )
                for index, member in enumerate(members, start=1):
                    processed += 1
                    prefix = (
                        f"wikipedia_sync: [{batch_category}] "
                        f"[{index}/{batch_total}] {member.title}"
                    )
                    try:
                        outcome = _process_member(
                            session,
                            wiki,
                            member,
                            dry_run=dry_run,
                            overwrite=overwrite,
                        )
                        if outcome == "types_added":
                            counters.types_added += 1
                            logger.info("%s action=types_added", prefix)
                        elif outcome == "revisions_appended":
                            counters.revisions_appended += 1
                            logger.info("%s action=revisions_appended", prefix)
                        elif outcome == "skip_same_hash":
                            counters.skipped += 1
                            logger.info("%s action=skip reason=same_hash", prefix)
                        elif outcome == "skip_current":
                            counters.skipped += 1
                            logger.info("%s action=skip reason=up_to_date", prefix)
                        elif outcome == "skip_disambiguation":
                            counters.disambiguation += 1
                            counters.skipped += 1
                            logger.warning(
                                "%s action=skip reason=disambiguation", prefix
                            )

                        if not dry_run and outcome in (
                            "types_added",
                            "revisions_appended",
                            "skip_same_hash",
                        ):
                            session.commit()
                    except Exception as exc:
                        counters.failed += 1
                        logger.error("%s action=failed error=%s", prefix, exc)
                        session.rollback()
                logger.info(
                    "wikipedia_sync: [%s] finished processed=%d",
                    batch_category,
                    batch_total,
                )
        except KeyboardInterrupt:
            interrupted = True
            logger.warning(
                "wikipedia_sync: interrupted after %d/%d records; progress committed through last successful record",
                processed,
                total,
            )
    finally:
        if own_client:
            wiki.close()

    elapsed = time.monotonic() - start
    summary = SyncSummary(
        category=cat,
        total_candidates=total,
        counters=counters,
        dry_run=dry_run,
        elapsed_s=elapsed,
    )
    logger.info(
        "wikipedia_sync: finished types_added=%d revisions_appended=%d skipped=%d "
        "failed=%d disambiguation=%d overwrite=%s dry_run=%s interrupted=%s elapsed_s=%.1f",
        counters.types_added,
        counters.revisions_appended,
        counters.skipped,
        counters.failed,
        counters.disambiguation,
        overwrite,
        dry_run,
        interrupted,
        elapsed,
    )
    if interrupted:
        raise KeyboardInterrupt
    return summary


def _process_member(
    session: Session,
    wiki: WikipediaClient,
    member: CategoryMember,
    *,
    dry_run: bool,
    overwrite: bool,
) -> str:
    metadata = fetch_page_metadata(wiki, member.title)
    if metadata.is_disambiguation:
        return "skip_disambiguation"

    existing = _find_existing(session, page_id=metadata.page_id, title=metadata.title)
    current = _current_revision(session, existing) if existing else None
    is_stale = _is_stale(current.article_date if current else None, metadata.article_date)
    incomplete = _is_incomplete(current)
    if existing and not overwrite and not is_stale and not incomplete:
        return "skip_current"

    payload = wiki.page_with_html(member.title)
    parsed = parse_article_html(str(payload.get("html", "")))
    new_hash = revision_content_hash(
        article=parsed.article_html,
        long_description=parsed.long_description,
        birth=parsed.birth,
        death=parsed.death,
        period=parsed.period,
        diet_type=parsed.diet_type,
        cladogram=parsed.cladogram,
    )

    if dry_run:
        if existing is None:
            return "types_added"
        if current is not None and current.content_hash == new_hash:
            return "skip_same_hash"
        return "revisions_appended"

    now = datetime.now(timezone.utc)
    if existing is None:
        row = DinosaurType(
            name=metadata.title,
            wikipedia_page_id=metadata.page_id,
            wikipedia_title=metadata.title,
            insert_date=now,
            main_image_url=metadata.image_url,
        )
        session.add(row)
        session.flush()
        revision = _build_revision(
            dinosaur_type_id=int(row.id),
            metadata=metadata,
            parsed=parsed,
        )
        session.add(revision)
        session.flush()
        row.current_revision_id = int(revision.id)
        session.add(row)
        return "types_added"

    # Identity / catalog image updates on the thin type row.
    existing.name = metadata.title
    existing.wikipedia_page_id = metadata.page_id
    existing.wikipedia_title = metadata.title
    if existing.main_image_url is None and metadata.image_url:
        existing.main_image_url = metadata.image_url

    if current is not None and current.content_hash == new_hash:
        # Absorb timestamp-only Wikipedia bumps without a new revision.
        if (
            metadata.article_date is not None
            and current.article_date != metadata.article_date
        ):
            current.article_date = metadata.article_date
            session.add(current)
        session.add(existing)
        return "skip_same_hash"

    # Content may have reverted to an older revision — reuse that row.
    prior = session.exec(
        select(DinosaurTypeRevision).where(
            DinosaurTypeRevision.dinosaur_type_id == existing.id,
            DinosaurTypeRevision.content_hash == new_hash,
        )
    ).first()
    if prior is not None:
        if (
            metadata.article_date is not None
            and prior.article_date != metadata.article_date
        ):
            prior.article_date = metadata.article_date
            session.add(prior)
        existing.current_revision_id = int(prior.id)
        session.add(existing)
        return "revisions_appended"

    revision = _build_revision(
        dinosaur_type_id=int(existing.id),
        metadata=metadata,
        parsed=parsed,
    )
    session.add(revision)
    session.flush()
    existing.current_revision_id = int(revision.id)
    session.add(existing)
    return "revisions_appended"


def sync_exit_code(summary: SyncSummary) -> int:
    """Return non-zero if failure rate exceeds configured threshold."""
    threshold = settings.wikipedia_sync_failure_threshold
    if summary.counters.failed == 0:
        return 0
    if summary.failure_rate > threshold:
        return 1
    return 0
