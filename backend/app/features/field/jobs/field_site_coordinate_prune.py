"""
Delete field sites whose coordinates fail the active land/water filter stack. Feature-owned implementation.

Run manually:
  python -m app.crons.runner --job field_site_coordinate_prune
  python -m app.crons.runner --job field_site_coordinate_prune --dry-run
"""

from __future__ import annotations

from sqlmodel import Session

from app.core.database import engine
from app.features.field.application.field_coordinate_filter import (
    ensure_osm_coordinate_masks_on_disk,
    warm_coordinate_filter_cache,
)
from app.features.field.application.field_coordinate_prune import (
    field_coordinate_prune_exit_code,
    prune_invalid_field_sites,
)


def run_prune_job(*, dry_run: bool = False) -> int:
    ensure_osm_coordinate_masks_on_disk()
    warm_coordinate_filter_cache()
    with Session(engine) as session:
        summary = prune_invalid_field_sites(session, dry_run=dry_run)
    return field_coordinate_prune_exit_code(summary)
