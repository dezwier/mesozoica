"""
Wikipedia dinosaur sync job. Feature-owned implementation.

Run manually:
  python -m app.crons.runner --job dinosaur_wiki_sync
  python -m app.crons.runner --job dinosaur_wiki_sync --overwrite
  python -m app.crons.runner --job dinosaur_wiki_sync --dinos Tyrannosaurus Giganotosaurus
  python -m app.crons.runner --job dinosaur_wiki_sync --category "Category:Feathered dinosaurs"
"""

from __future__ import annotations

from sqlmodel import Session

from app.core.database import engine
from app.features.ingestion.infrastructure.wikipedia.sync import sync_dinosaurs, sync_exit_code


def run_sync_job(
    *,
    dry_run: bool = False,
    overwrite: bool = False,
    max_pages: int | None = None,
    category: str | None = None,
    dinos: list[str] | None = None,
) -> int:
    with Session(engine) as session:
        summary = sync_dinosaurs(
            session,
            category=category,
            max_pages=max_pages,
            dry_run=dry_run,
            overwrite=overwrite,
            dinos=dinos,
        )
    return sync_exit_code(summary)
