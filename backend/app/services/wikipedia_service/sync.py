"""Orchestrate Wikipedia dinosaur sync into the database."""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone

from sqlmodel import Session, select

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


def _get_by_page_id(session: Session, page_id: int) -> Dinosaur | None:
    return session.exec(select(Dinosaur).where(Dinosaur.wikipedia_page_id == page_id)).first()


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
            short_description=metadata.description,
            long_description=parsed.long_description,
            article=parsed.article_html,
            article_date=metadata.article_date,
            insert_date=now,
        )
        return row

    existing.name = title
    existing.wikipedia_title = title
    existing.birth = parsed.birth
    existing.death = parsed.death
    existing.period = parsed.period
    existing.cladogram = parsed.cladogram
    existing.diet_type = parsed.diet_type
    existing.short_description = metadata.description
    existing.long_description = parsed.long_description
    existing.article = parsed.article_html
    existing.article_date = metadata.article_date
    return existing


def sync_dinosaurs(
    session: Session,
    *,
    category: str | None = None,
    max_pages: int | None = None,
    dry_run: bool = False,
    client: WikipediaClient | None = None,
) -> SyncSummary:
    """Sync dinosaur records from Wikipedia category into the database."""
    cat = category or settings.wikipedia_dinosaur_category
    cap = max_pages if max_pages is not None else settings.wikipedia_sync_max_pages
    start = time.monotonic()
    counters = SyncCounters()

    own_client = client is None
    wiki = client or WikipediaClient()
    members: list[CategoryMember] = []
    try:
        members = list_category_articles(wiki, cat, max_pages=cap)
        total = len(members)
        logger.info("wikipedia_sync: starting category=%s total_candidates=%d", cat, total)

        for index, member in enumerate(members, start=1):
            prefix = f"[{index}/{total}] {member.title}"
            try:
                outcome = _process_member(session, wiki, member, dry_run=dry_run)
                if outcome == "fetch_new":
                    counters.fetched += 1
                    logger.info("%s action=fetch reason=new", prefix)
                elif outcome == "fetch_update":
                    counters.updated += 1
                    logger.info("%s action=fetch reason=stale", prefix)
                elif outcome == "skip_current":
                    counters.skipped += 1
                    logger.info("%s action=skip reason=up_to_date", prefix)
                elif outcome == "skip_disambiguation":
                    counters.disambiguation += 1
                    counters.skipped += 1
                    logger.warning("%s action=skip reason=disambiguation", prefix)
            except Exception as exc:
                counters.failed += 1
                logger.error("%s action=failed error=%s", prefix, exc)
                session.rollback()

        if not dry_run:
            session.commit()
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
        "disambiguation=%d dry_run=%s elapsed_s=%.1f",
        counters.fetched,
        counters.updated,
        counters.skipped,
        counters.failed,
        counters.disambiguation,
        dry_run,
        elapsed,
    )
    return summary


def _process_member(
    session: Session,
    wiki: WikipediaClient,
    member: CategoryMember,
    *,
    dry_run: bool,
) -> str:
    metadata = fetch_page_metadata(wiki, member.title)
    if metadata.is_disambiguation:
        return "skip_disambiguation"

    existing = _get_by_page_id(session, metadata.page_id)
    if existing and not _is_stale(existing.article_date, metadata.article_date):
        return "skip_current"

    payload = wiki.page_with_html(member.title)
    parsed = parse_article_html(str(payload.get("html", "")))
    row = _apply_parsed(existing, title=metadata.title, page_id=metadata.page_id, metadata=metadata, parsed=parsed)

    if dry_run:
        return "fetch_new" if existing is None else "fetch_update"

    if existing is None:
        session.add(row)
        return "fetch_new"

    session.add(row)
    return "fetch_update"


def sync_exit_code(summary: SyncSummary) -> int:
    """Return non-zero if failure rate exceeds configured threshold."""
    threshold = settings.wikipedia_sync_failure_threshold
    if summary.counters.failed == 0:
        return 0
    if summary.failure_rate > threshold:
        return 1
    return 0
