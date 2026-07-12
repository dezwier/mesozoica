"""
Fossil clean table rebuild job.

Run manually:
  python -m app.crons.runner --job fossil_clean_sync
  python -m app.crons.runner --job fossil_clean_sync --dry-run
  python -m app.crons.runner --job fossil_clean_sync --dinos Tyrannosaurus
"""

from __future__ import annotations

from sqlmodel import Session

from app.core.database import engine
from app.services.fossil_clean_service.sync import sync_clean_tables, sync_exit_code


def run_sync_job(
    *,
    dry_run: bool = False,
    dinos: list[str] | None = None,
) -> int:
    with Session(engine) as session:
        summary = sync_clean_tables(session, dry_run=dry_run, dinos=dinos)
    return sync_exit_code(summary)
