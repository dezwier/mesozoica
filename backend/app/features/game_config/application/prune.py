"""Trim old game config revisions. Feature-owned implementation."""

from __future__ import annotations

import logging

from sqlmodel import Session, select

from app.models.game_config_revision import GameConfigRevision
from app.features.game_config.application.read import read_release

logger = logging.getLogger(__name__)

KEEP_REVISIONS = 200


def prune_revisions(
    session: Session, *, keep: int = KEEP_REVISIONS, dry_run: bool = False
) -> int:
    """Delete all but the newest ``keep`` revisions. Never deletes the active one."""
    release = read_release(session)
    active_id = release.revision_id if release else None

    rows = session.exec(
        select(GameConfigRevision).order_by(GameConfigRevision.version.desc())
    ).all()
    doomed = [row for row in rows[keep:] if row.id != active_id]
    if not doomed:
        return 0

    if dry_run:
        logger.info(
            "game_config prune dry-run: would delete %d revision(s) (oldest kept version=%s)",
            len(doomed),
            rows[keep - 1].version if len(rows) >= keep else None,
        )
        return len(doomed)

    for row in doomed:
        session.delete(row)
    session.commit()
    logger.info("game_config pruned %d revision(s)", len(doomed))
    return len(doomed)
