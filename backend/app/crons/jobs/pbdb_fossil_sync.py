"""
PBDB fossil occurrence sync job.

Run manually:
  python -m app.crons.runner --job pbdb_fossil_sync
  python -m app.crons.runner --job pbdb_fossil_sync --overwrite
  python -m app.crons.runner --job pbdb_fossil_sync --stale-days 7
  python -m app.crons.runner --job pbdb_fossil_sync --dinos Tyrannosaurus Giganotosaurus
  python -m app.crons.runner --job pbdb_fossil_sync --dinos Tyrannosaurus --overwrite
"""

from __future__ import annotations

from datetime import datetime

from sqlmodel import Session

from app.core.database import engine
from app.services.pbdb_service.sync import sync_exit_code, sync_fossils


def run_sync_job(
    *,
    dry_run: bool = False,
    overwrite: bool = False,
    dinos: list[str] | None = None,
    since: datetime | None = None,
    stale_days: int | None = None,
) -> int:
    with Session(engine) as session:
        summary = sync_fossils(
            session,
            dry_run=dry_run,
            overwrite=overwrite,
            dinos=dinos,
            since=since,
            stale_days=stale_days,
        )
    return sync_exit_code(summary)
