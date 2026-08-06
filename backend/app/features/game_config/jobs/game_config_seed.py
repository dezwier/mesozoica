"""
Game config seed job: publish the bundled YAML control board into the database. Feature-owned implementation.

The database is the source of truth once seeded, so this is a no-op when a
revision already exists — pass --force to publish the repo YAML as a new
revision (overwriting admin edits).

Run manually:
  python -m app.crons.runner --job game_config_seed --dry-run
  python -m app.crons.runner --job game_config_seed
  python -m app.crons.runner --job game_config_seed --force
  python -m app.crons.runner --job game_config_seed --prune
"""

from __future__ import annotations

import logging

from sqlmodel import Session

from app.core.database import engine
from app.features.game_config.application.prune import prune_revisions
from app.features.game_config.application.seed import seed_from_yaml

logger = logging.getLogger(__name__)


def run_seed_job(
    *,
    dry_run: bool = False,
    force: bool = False,
    prune: bool = False,
    note: str = "",
) -> int:
    with Session(engine) as session:
        summary = seed_from_yaml(
            session, dry_run=dry_run, force=force, note=note
        )
        logger.info(
            "game_config_seed created=%s version=%s changed=%s dry_run=%s",
            summary.created,
            summary.version,
            ",".join(summary.changed_doc_ids) or "-",
            summary.dry_run,
        )
        if prune:
            deleted = prune_revisions(session, dry_run=dry_run)
            logger.info("game_config_seed pruned=%d dry_run=%s", deleted, dry_run)
    return 0
