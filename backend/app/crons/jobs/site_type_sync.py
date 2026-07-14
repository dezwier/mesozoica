"""
Site type table rebuild job.

Run manually:
  python -m app.crons.runner --job site_type_sync
  python -m app.crons.runner --job site_type_sync --dry-run
  python -m app.crons.runner --job site_type_sync --dinos Tyrannosaurus
"""

from __future__ import annotations

from sqlmodel import Session

from app.core.database import engine
from app.services.site_service.site_type_sync import (
    site_type_sync_exit_code,
    sync_site_types,
)


def run_sync_job(
    *,
    dry_run: bool = False,
    dinos: list[str] | None = None,
) -> int:
    with Session(engine) as session:
        summary = sync_site_types(session, dry_run=dry_run, dinos=dinos)
    return site_type_sync_exit_code(summary)
