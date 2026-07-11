"""Orchestrate Wikipedia dinosaur sync into the database."""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone

from sqlmodel import Session, select, update

from app.core.config import settings
from app.models.dinosaur import Dinosaur
from app.services.wikipedia_service.category import CategoryMember, list_category_articles
from app.services.wikipedia_service.client import WikipediaClient
from app.services.wikipedia_service.metadata import fetch_page_metadata
from app.services.wikipedia_service.parser import parse_article_html

logger = logging.getLogger("wikipedia_sync")


@dataclass
class SyncCounters:
    fetched: int = 0
    updated: int = 0
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
        attempted = self.counters.fetched + self.counters.updated + self.counters.failed
        if attempted == 0:
            return 0.0
        return self.counters.failed / attempted


def _is_stale(db_date: datetime | None, wiki_date: datetime) -> bool:
    if db_date is None:
        return True
    db_aware = db_date if db_date.tzinfo else db_date.replace(tzinfo=timezone.utc)
    wiki_aware = wiki_date if wiki_date.tzinfo else wiki_date.replace(tzinfo=timezone.utc)
    return wiki_aware > db_aware


def _is_incomplete(existing: Dinosaur) -> bool:
    """True when a row looks synced but is missing core Wikipedia payload."""
    if not (existing.article or "").strip():
        return True
    if not existing.cladogram:
        return True
    return False


def _get_by_page_id(session: Session, page_id: int) -> Dinosaur | None:
    return session.exec(select(Dinosaur).where(Dinosaur.wikipedia_page_id == page_id)).first()


def _find_existing(session: Session, *, page_id: int, title: str) -> Dinosaur | None:
    """Match by Wikipedia page id, then fall back to title for legacy stub rows."""
    by_page_id = _get_by_page_id(session, page_id)
    if by_page_id is not None:
        return by_page_id
    return session.exec(
        select(Dinosaur).where(Dinosaur.wikipedia_title == title)
    ).first()


def _clear_llm_enrichment_fields(dinosaur: Dinosaur) -> None:
    """Drop LLM-only fields so stale enrichment is not shown after a Wikipedia refresh."""
    dinosaur.length = None
    dinosaur.mass = None
    dinosaur.location = None
    dinosaur.short_description = None
    dinosaur.llm_enriched = False


def _bulk_clear_llm_enrichment_fields(session: Session, *, dry_run: bool) -> int:
    """Clear LLM-only columns on every dinosaur row (used with --overwrite)."""
    if dry_run:
        stmt = select(Dinosaur).where(
            (Dinosaur.length.is_not(None))  # type: ignore[union-attr]
            | (Dinosaur.mass.is_not(None))  # type: ignore[union-attr]
            | (Dinosaur.location.is_not(None))  # type: ignore[union-attr]
            | (Dinosaur.short_description.is_not(None))  # type: ignore[union-attr]
            | (Dinosaur.llm_enriched.is_(True))  # type: ignore[attr-defined]
        )
        return len(list(session.exec(stmt).all()))

    result = session.exec(
        update(Dinosaur).values(
            length=None,
            mass=None,
            location=None,
            short_description=None,
            llm_enriched=False,
        )
    )
    session.commit()
    return int(result.rowcount or 0)


def _apply_parsed(existing: Dinosaur | None, *, title: str, page_id: int, metadata, parsed) -> Dinosaur:
    now = datetime.now(timezone.utc)
    if existing is None:
        row = Dinosaur(
            name=title,
            wikipedia_page_id=page_id,
            wikipedia_title=title,
            birth=parsed.birth,
            death=parsed.death,
            period=parsed.period,
            cladogram=parsed.cladogram,
            diet_type=parsed.diet_type,
            long_description=parsed.long_description,
            article=parsed.article_html,
            article_date=metadata.article_date,
            insert_date=now,
            main_image_url=metadata.image_url,
        )
        return row

    existing.name = title
    existing.wikipedia_page_id = page_id
    existing.wikipedia_title = title
    existing.birth = parsed.birth
    existing.death = parsed.death
    existing.period = parsed.period
    existing.cladogram = parsed.cladogram
    existing.diet_type = parsed.diet_type
    existing.long_description = parsed.long_description
    existing.article = parsed.article_html
    existing.article_date = metadata.article_date
    if existing.main_image_url is None and metadata.image_url:
        existing.main_image_url = metadata.image_url
    _clear_llm_enrichment_fields(existing)
    return existing


def sync_dinosaurs(
    session: Session,
    *,
    category: str | None = None,
    max_pages: int | None = None,
    dry_run: bool = False,
    overwrite: bool = False,
    client: WikipediaClient | None = None,
) -> SyncSummary:
    """Sync dinosaur records from Wikipedia category into the database."""
    cat = category or settings.wikipedia_dinosaur_category
    cap = max_pages if max_pages is not None else settings.wikipedia_sync_max_pages
    start = time.monotonic()
    counters = SyncCounters()
    interrupted = False
    processed = 0

    own_client = client is None
    wiki = client or WikipediaClient()
    members: list[CategoryMember] = []
    try:
        if overwrite and not dry_run:
            cleared = _bulk_clear_llm_enrichment_fields(session, dry_run=False)
            logger.info(
                "wikipedia_sync: cleared LLM fields on %d dinosaur row(s) before overwrite refresh",
                cleared,
            )
        elif overwrite and dry_run:
            would_clear = _bulk_clear_llm_enrichment_fields(session, dry_run=True)
            logger.info(
                "wikipedia_sync: dry_run would clear LLM fields on %d dinosaur row(s)",
                would_clear,
            )

        members = list_category_articles(wiki, cat, max_pages=cap)
        total = len(members)
        logger.info(
            "wikipedia_sync: starting category=%s total_candidates=%d overwrite=%s",
            cat,
            total,
            overwrite,
        )

        try:
            for index, member in enumerate(members, start=1):
                processed = index
                prefix = f"wikipedia_sync: [{index}/{total}] {member.title}"
                try:
                    outcome = _process_member(
                        session,
                        wiki,
                        member,
                        dry_run=dry_run,
                        overwrite=overwrite,
                    )
                    if outcome == "fetch_new":
                        counters.fetched += 1
                        logger.info("%s action=fetch reason=new", prefix)
                    elif outcome == "fetch_update_stale":
                        counters.updated += 1
                        logger.info("%s action=fetch reason=stale", prefix)
                    elif outcome == "fetch_update_incomplete":
                        counters.updated += 1
                        logger.info("%s action=fetch reason=incomplete", prefix)
                    elif outcome == "fetch_update_overwrite":
                        counters.updated += 1
                        logger.info("%s action=fetch reason=overwrite", prefix)
                    elif outcome == "skip_current":
                        counters.skipped += 1
                        logger.info("%s action=skip reason=up_to_date", prefix)
                    elif outcome == "skip_disambiguation":
                        counters.disambiguation += 1
                        counters.skipped += 1
                        logger.warning("%s action=skip reason=disambiguation", prefix)

                    if not dry_run and outcome in (
                        "fetch_new",
                        "fetch_update_stale",
                        "fetch_update_incomplete",
                        "fetch_update_overwrite",
                    ):
                        session.commit()
                except Exception as exc:
                    counters.failed += 1
                    logger.error("%s action=failed error=%s", prefix, exc)
                    session.rollback()
        except KeyboardInterrupt:
            interrupted = True
            logger.warning(
                "wikipedia_sync: interrupted at [%d/%d]; progress committed through last successful record",
                processed,
                total,
            )
    finally:
        if own_client:
            wiki.close()

    elapsed = time.monotonic() - start
    summary = SyncSummary(
        category=cat,
        total_candidates=len(members),
        counters=counters,
        dry_run=dry_run,
        elapsed_s=elapsed,
    )
    logger.info(
        "wikipedia_sync: finished fetched=%d updated=%d skipped=%d failed=%d "
        "disambiguation=%d overwrite=%s dry_run=%s interrupted=%s elapsed_s=%.1f",
        counters.fetched,
        counters.updated,
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
    is_stale = _is_stale(existing.article_date if existing else None, metadata.article_date)
    incomplete = existing is not None and _is_incomplete(existing)
    if existing and not overwrite and not is_stale and not incomplete:
        return "skip_current"

    payload = wiki.page_with_html(member.title)
    parsed = parse_article_html(str(payload.get("html", "")))
    row = _apply_parsed(existing, title=metadata.title, page_id=metadata.page_id, metadata=metadata, parsed=parsed)

    if dry_run:
        if existing is None:
            return "fetch_new"
        if overwrite and not is_stale:
            return "fetch_update_overwrite"
        if incomplete:
            return "fetch_update_incomplete"
        return "fetch_update_stale"

    if existing is None:
        session.add(row)
        return "fetch_new"

    session.add(row)
    if overwrite and not is_stale:
        return "fetch_update_overwrite"
    if incomplete:
        return "fetch_update_incomplete"
    return "fetch_update_stale"


def sync_exit_code(summary: SyncSummary) -> int:
    """Return non-zero if failure rate exceeds configured threshold."""
    threshold = settings.wikipedia_sync_failure_threshold
    if summary.counters.failed == 0:
        return 0
    if summary.failure_rate > threshold:
        return 1
    return 0
