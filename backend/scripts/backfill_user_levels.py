"""Recompute user skill XP from discoveries + distance using current leveling.yaml."""

from __future__ import annotations

import argparse
import logging
import sys

from sqlmodel import Session, select

from app.core.database import engine
from app.core.game_config import get_game_config
from app.crons.railway_guard import require_railway_database
from app.models.user import User
from app.services.level_service.backfill import backfill_user_levels

logger = logging.getLogger(__name__)


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Backfill skill / career XP for all users from site & fossil "
            "discoveries plus walked distance, using rewards in leveling.yaml."
        )
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print what would change without writing to the database.",
    )
    return parser.parse_args()


def main() -> int:
    args = _parse_args()
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")

    if not args.dry_run:
        require_railway_database()

    get_game_config.cache_clear()
    rewards = get_game_config().leveling.rewards
    logger.info(
        "rewards site_discovery=%s fossil_detection=%s active_km=%s passive_km=%s",
        rewards.site_discover_site_discovery_xp,
        rewards.fossil_discover_fossil_detection_xp,
        rewards.active_km_site_discovery_xp,
        rewards.passive_km_site_discovery_xp,
    )

    with Session(engine) as session:
        users = list(session.exec(select(User)).all())
        logger.info("users=%s dry_run=%s", len(users), args.dry_run)
        for user in users:
            before = int((user.skill_xp or {}).get("site_discovery", 0))
            backfill_user_levels(session, user)
            after = int((user.skill_xp or {}).get("site_discovery", 0))
            logger.info(
                "user id=%s username=%s site_discovery_xp %s -> %s (level %s)",
                user.id,
                user.username,
                before,
                after,
                user.level,
            )
        if args.dry_run:
            session.rollback()
            logger.info("dry-run complete (no writes)")
        else:
            session.commit()
            logger.info("committed %s users", len(users))

    return 0


if __name__ == "__main__":
    sys.exit(main())
