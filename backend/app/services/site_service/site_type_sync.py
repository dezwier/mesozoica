"""Upsert site_type rows and assign site.site_type_id from site data."""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field

from sqlmodel import Session, col, select

from app.models.dinosaur_type import DinosaurType
from app.models.data_source import DATA_SOURCE_ARCHIVE
from app.models.fossil import Fossil
from app.models.site import Site
from app.models.site_type import SiteType
from app.services.dinosaur_name_filter import dino_name_match_clause
from app.services.site_service.rules import period_for_ages
from app.services.site_service.site_type_fallback import (
    load_site_types_by_period,
    period_to_type_ids,
    pick_site_type_id_for_period,
)

logger = logging.getLogger("site_type_sync")


@dataclass
class SiteTypeSyncCounters:
    site_types_written: int = 0
    sites_updated: int = 0


@dataclass
class SiteTypeSyncSummary:
    total_sites: int
    counters: SiteTypeSyncCounters = field(default_factory=SiteTypeSyncCounters)
    dry_run: bool = False
    partial: bool = False
    elapsed_s: float = 0.0


def _sites_query(session: Session, *, dinos: list[str] | None):
    """Return sites to assign. Full sync includes archive + field; --dinos is archive-only."""
    if dinos:
        return (
            select(Site)
            .where(col(Site.data_source) == DATA_SOURCE_ARCHIVE)
            .join(Fossil, col(Fossil.site_id) == col(Site.site_id))
            .join(DinosaurType, col(Fossil.dinosaur_id) == col(DinosaurType.id))
            .where(dino_name_match_clause(dinos))
            .distinct()
        )
    return select(Site)


def _site_type_pairs(sites: list[Site]) -> set[tuple[str, str]]:
    pairs: set[tuple[str, str]] = set()
    for site in sites:
        period = period_for_ages(site.min_age_ma, site.max_age_ma)
        if period and site.rock_type:
            pairs.add((period, site.rock_type))
    return pairs


def _write_site_types(
    session: Session,
    pairs: set[tuple[str, str]],
) -> dict[tuple[str, str], int]:
    """Upsert by (period, rock_type): reuse existing rows, insert missing ones. Never deletes."""
    mapping: dict[tuple[str, str], int] = {}
    for period, rock_type in sorted(pairs):
        stmt = select(SiteType).where(
            SiteType.period == period,
            SiteType.rock_type == rock_type,
        )
        row = session.exec(stmt).first()
        if row is None:
            row = SiteType(period=period, rock_type=rock_type)
            session.add(row)
            session.flush()
            if row.id is None:
                session.refresh(row)
        mapping[(period, rock_type)] = row.id

    return mapping


def _assign_site_type_id(
    site: Site,
    *,
    site_type_ids: dict[tuple[str, str], int],
    period_to_ids: dict[str, list[int]],
) -> int | None:
    period = period_for_ages(site.min_age_ma, site.max_age_ma)
    if period and site.rock_type:
        return site_type_ids.get((period, site.rock_type))
    if period and not (site.rock_type or "").strip():
        return pick_site_type_id_for_period(
            site_id=site.site_id,
            period=period,
            period_to_type_ids=period_to_ids,
        )
    return None


def sync_site_types(
    session: Session,
    *,
    dry_run: bool = False,
    dinos: list[str] | None = None,
) -> SiteTypeSyncSummary:
    """Upsert ``site_type`` rows and set ``site.site_type_id`` from existing sites.

    Never deletes ``site_type`` rows, so existing FKs (including field sites) stay valid.
    Missing ``(period, rock_type)`` pairs are inserted; existing rows keep their ids and
    ``main_image_url``.
    """
    started = time.monotonic()
    sites = list(session.exec(_sites_query(session, dinos=dinos)).all())
    site_type_pairs = _site_type_pairs(sites)

    counters = SiteTypeSyncCounters(
        site_types_written=len(site_type_pairs),
        sites_updated=len(sites),
    )
    summary = SiteTypeSyncSummary(
        total_sites=len(sites),
        counters=counters,
        dry_run=dry_run,
        partial=bool(dinos),
        elapsed_s=time.monotonic() - started,
    )

    logger.info(
        "%s action=summary sites=%d site_types=%d dry_run=%s partial=%s",
        "site_type_sync",
        summary.total_sites,
        counters.site_types_written,
        dry_run,
        summary.partial,
    )

    if dry_run:
        return summary

    site_type_ids = _write_site_types(session, site_type_pairs)
    period_to_ids = period_to_type_ids(load_site_types_by_period(session))

    for site in sites:
        site.site_type_id = _assign_site_type_id(
            site,
            site_type_ids=site_type_ids,
            period_to_ids=period_to_ids,
        )

    session.commit()

    return summary


def site_type_sync_exit_code(_summary: SiteTypeSyncSummary) -> int:
    return 0
