"""Delete field sites that fail the current coordinate filter stack."""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass

from sqlalchemy import func
from sqlmodel import Session, col, delete, select

from app.models.data_source import DATA_SOURCE_FIELD
from app.models.site import Site
from app.services.site_service.field_coordinate_filter import build_coordinate_filter

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class FieldCoordinatePruneSummary:
    checked: int = 0
    deleted: int = 0
    kept: int = 0
    dry_run: bool = False
    elapsed_s: float = 0.0


def prune_invalid_field_sites(
    session: Session,
    *,
    dry_run: bool = False,
    batch_size: int = 5000,
) -> FieldCoordinatePruneSummary:
    """Remove field sites whose coordinates fail the active filter stack."""
    started = time.monotonic()
    coordinate_filter = build_coordinate_filter()
    checked = 0
    deleted = 0
    kept = 0
    last_site_id = 0

    while True:
        stmt = (
            select(Site)
            .where(col(Site.data_source) == DATA_SOURCE_FIELD)
            .where(col(Site.site_id) > last_site_id)
            .where(col(Site.latitude).is_not(None))
            .where(col(Site.longitude).is_not(None))
            .order_by(col(Site.site_id))
            .limit(batch_size)
        )
        rows = list(session.exec(stmt).all())
        if not rows:
            break

        invalid_ids: list[int] = []
        for row in rows:
            checked += 1
            last_site_id = row.site_id
            lat = float(row.latitude)
            lon = float(row.longitude)
            if coordinate_filter.allows(lat, lon):
                kept += 1
            else:
                invalid_ids.append(row.site_id)

        if invalid_ids:
            deleted += len(invalid_ids)
            if not dry_run:
                session.exec(delete(Site).where(col(Site.site_id).in_(invalid_ids)))
                session.commit()

    summary = FieldCoordinatePruneSummary(
        checked=checked,
        deleted=deleted,
        kept=kept,
        dry_run=dry_run,
        elapsed_s=time.monotonic() - started,
    )
    logger.info(
        "field_site_coordinate_prune checked=%d deleted=%d kept=%d dry_run=%s elapsed_s=%.2f",
        summary.checked,
        summary.deleted,
        summary.kept,
        summary.dry_run,
        summary.elapsed_s,
    )
    return summary


def field_coordinate_prune_exit_code(summary: FieldCoordinatePruneSummary) -> int:
    return 0
