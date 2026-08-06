"""Rebuild the site table from raw fossil data and link fossil.site_id."""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field

from sqlalchemy import delete, update
from sqlmodel import Session, col

from app.models.fossil import Fossil
from app.shared.data_sources import DATA_SOURCE_ARCHIVE
from app.models.site import Site
from app.features.sites.application.build import (
    apply_site_draft,
    build_site_draft,
    fossil_query,
    linkable_fossils,
    site_members,
)

logger = logging.getLogger("site_sync")


@dataclass
class SiteSyncCounters:
    sites_written: int = 0
    fossils_linked: int = 0
    fossils_skipped: int = 0


@dataclass
class SiteSyncSummary:
    total_source_fossils: int
    counters: SiteSyncCounters = field(default_factory=SiteSyncCounters)
    dry_run: bool = False
    partial: bool = False
    elapsed_s: float = 0.0


def sync_sites(
    session: Session,
    *,
    dry_run: bool = False,
    dinos: list[str] | None = None,
) -> SiteSyncSummary:
    """Rebuild ``site`` from the raw ``fossil`` table and set ``fossil.site_id``."""
    started = time.monotonic()
    source_fossils = list(session.exec(fossil_query(session, dinos=dinos)).all())
    counters = SiteSyncCounters()

    fossils_to_link, counters.fossils_skipped = linkable_fossils(source_fossils)
    collection_nos = {fossil.collection_no for fossil in fossils_to_link}
    members = site_members(session, collection_nos)
    site_drafts = [
        draft
        for site_id, fossils_at_site in sorted(members.items())
        if (draft := build_site_draft(site_id, fossils_at_site)) is not None
    ]
    site_rows = [draft.site for draft in site_drafts]

    counters.fossils_linked = len(fossils_to_link)
    counters.sites_written = len(site_rows)

    summary = SiteSyncSummary(
        total_source_fossils=len(source_fossils),
        counters=counters,
        dry_run=dry_run,
        partial=bool(dinos),
        elapsed_s=time.monotonic() - started,
    )

    logger.info(
        "%s action=summary source_fossils=%d sites=%d fossils_linked=%d skipped=%d "
        "dry_run=%s partial=%s",
        "site_sync",
        summary.total_source_fossils,
        counters.sites_written,
        counters.fossils_linked,
        counters.fossils_skipped,
        dry_run,
        summary.partial,
    )

    if dry_run:
        return summary

    site_ids = {row.site_id for row in site_rows}
    missing_site_ids = collection_nos - site_ids
    if missing_site_ids:
        sample = sorted(missing_site_ids)[:10]
        raise RuntimeError(
            f"fossil site_id references {len(missing_site_ids)} site(s) missing from site table; "
            f"sample={sample}"
        )

    full_refresh = not dinos

    if full_refresh:
        session.exec(delete(Site).where(col(Site.data_source) == DATA_SOURCE_ARCHIVE))
        session.flush()
        for site_row in site_rows:
            session.add(site_row)
        session.flush()
        session.exec(
            update(Fossil)
            .values(site_id=None)
            .where(
                col(Fossil.collection_no).is_(None),
                col(Fossil.data_source) == DATA_SOURCE_ARCHIVE,
            )
        )
        for fossil in fossils_to_link:
            fossil.site_id = fossil.collection_no
    else:
        for draft in site_drafts:
            existing = session.get(Site, draft.site.site_id)
            if existing is None:
                session.add(draft.site)
            elif existing.data_source == DATA_SOURCE_ARCHIVE:
                apply_site_draft(existing, draft.site)
        session.flush()
        for fossil in fossils_to_link:
            fossil.site_id = fossil.collection_no

    session.commit()

    return summary


def site_sync_exit_code(summary: SiteSyncSummary) -> int:
    if summary.counters.fossils_skipped > 0:
        return 1
    return 0
