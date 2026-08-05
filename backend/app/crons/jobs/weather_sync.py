"""
Sync 15-minute past + forecast weather for cells with active field sites.

Run manually:
  python -m app.crons.runner --job weather_sync
  python -m app.crons.runner --job weather_sync --dry-run
"""

from __future__ import annotations

import logging

from sqlmodel import Session

from app.core.database import engine
from app.services.weather_service.persist import sync_weather_for_active_cells

logger = logging.getLogger(__name__)


def run_sync_job(
    *,
    dry_run: bool = False,
    past_days: int = 2,
    forecast_days: int = 3,
    batch_size: int = 50,
    prune_days: int = 7,
) -> int:
    with Session(engine) as session:
        summary = sync_weather_for_active_cells(
            session,
            past_days=past_days,
            forecast_days=forecast_days,
            batch_size=batch_size,
            prune_days=prune_days,
            dry_run=dry_run,
        )
    logger.info(
        "weather_sync cells=%s upserted=%s pruned=%s errors=%s dry_run=%s",
        summary.cells,
        summary.upserted,
        summary.pruned,
        summary.errors,
        summary.dry_run,
    )
    return 1 if summary.errors and summary.upserted == 0 else 0
