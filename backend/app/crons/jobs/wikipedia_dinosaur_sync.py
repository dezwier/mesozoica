"""
Wikipedia dinosaur sync job.

Run manually:
  python -m app.crons.runner --job wikipedia_dinosaur_sync
"""

from __future__ import annotations

from sqlmodel import Session

from app.core.database import engine
from app.services.wikipedia_service.sync import sync_dinosaurs, sync_exit_code


def run_sync_job(
    *,
    dry_run: bool = False,
    max_pages: int | None = None,
    category: str | None = None,
) -> int:
    with Session(engine) as session:
        summary = sync_dinosaurs(
            session,
            category=category,
            max_pages=max_pages,
            dry_run=dry_run,
        )
    return sync_exit_code(summary)
