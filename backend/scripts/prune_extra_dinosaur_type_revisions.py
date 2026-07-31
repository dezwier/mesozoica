"""Keep one original dinosaur_type_revision per type; delete extras.

Keeps the earliest revision per dinosaur_type (by created_at, then id) — the
migration backfill / first sync row. Re-points dinosaur_type.current_revision_id
and dinosaur.dinosaur_type_revision_id, then deletes newer revisions.

Usage (Railway DB):
  cd backend && RAILWAY_RUN=1 railway run python -m scripts.prune_extra_dinosaur_type_revisions
  cd backend && RAILWAY_RUN=1 railway run python -m scripts.prune_extra_dinosaur_type_revisions --apply
"""

from __future__ import annotations

import argparse
import logging

from sqlalchemy import delete, func, update
from sqlmodel import Session, col, select

from app.core.database import engine
from app.crons.railway_guard import require_railway_database
from app.models.dinosaur import Dinosaur
from app.models.dinosaur_type import DinosaurType
from app.models.dinosaur_type_revision import DinosaurTypeRevision

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
logger = logging.getLogger("prune_dino_revisions")


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Prune extra dinosaur_type_revision rows; keep one original per type."
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Persist changes. Default is dry-run (report only).",
    )
    return parser.parse_args()


def _earliest_revisions_by_type(
    session: Session,
) -> dict[int, tuple[DinosaurTypeRevision, list[int]]]:
    """Map type_id -> (keep_revision, doomed_revision_ids)."""
    type_ids = list(session.exec(select(DinosaurType.id)).all())
    result: dict[int, tuple[DinosaurTypeRevision, list[int]]] = {}
    for type_id in type_ids:
        rows = list(
            session.exec(
                select(DinosaurTypeRevision)
                .where(col(DinosaurTypeRevision.dinosaur_type_id) == type_id)
                .order_by(
                    col(DinosaurTypeRevision.created_at).asc(),
                    col(DinosaurTypeRevision.id).asc(),
                )
            ).all()
        )
        if not rows:
            continue
        keep = rows[0]
        doomed = [int(r.id) for r in rows[1:]]
        result[int(type_id)] = (keep, doomed)
    return result


def prune_extra_revisions(session: Session, *, apply: bool) -> dict[str, int]:
    """Keep earliest revision per type; remount FKs; delete the rest."""
    by_type = _earliest_revisions_by_type(session)
    types_with_extras = sum(1 for _, doomed in by_type.values() if doomed)
    delete_ids = [rid for _, doomed in by_type.values() for rid in doomed]

    stats = {
        "types": len(by_type),
        "types_with_extras": types_with_extras,
        "revisions_kept": len(by_type),
        "revisions_to_delete": len(delete_ids),
        "occurrences_remounted": 0,
        "types_current_updated": 0,
        "revisions_deleted": 0,
    }

    logger.info(
        "prune_dino_revisions: types=%d with_extras=%d keep=%d delete=%d apply=%s",
        stats["types"],
        stats["types_with_extras"],
        stats["revisions_kept"],
        stats["revisions_to_delete"],
        apply,
    )

    if not delete_ids:
        logger.info("prune_dino_revisions: nothing to delete")
        return stats

    sample = session.exec(
        select(DinosaurType.name, func.count(DinosaurTypeRevision.id))
        .join(
            DinosaurTypeRevision,
            col(DinosaurTypeRevision.dinosaur_type_id) == col(DinosaurType.id),
        )
        .group_by(DinosaurType.name)
        .having(func.count(DinosaurTypeRevision.id) > 1)
        .order_by(func.count(DinosaurTypeRevision.id).desc())
        .limit(15)
    ).all()
    for name, count in sample:
        logger.info("  sample extras: %s revisions=%d", name, count)

    if not apply:
        return stats

    for type_id, (keep, doomed) in by_type.items():
        if not doomed:
            # Still ensure current points at the sole revision.
            dino_type = session.get(DinosaurType, type_id)
            if dino_type is not None and dino_type.current_revision_id != keep.id:
                dino_type.current_revision_id = int(keep.id)
                session.add(dino_type)
                stats["types_current_updated"] += 1
            continue

        keep_id = int(keep.id)
        remount = session.exec(
            update(Dinosaur)
            .where(col(Dinosaur.dinosaur_type_revision_id).in_(doomed))
            .values(dinosaur_type_revision_id=keep_id)
        )
        stats["occurrences_remounted"] += int(remount.rowcount or 0)

        dino_type = session.get(DinosaurType, type_id)
        if dino_type is not None and dino_type.current_revision_id != keep_id:
            dino_type.current_revision_id = keep_id
            session.add(dino_type)
            stats["types_current_updated"] += 1

    session.flush()

    # Break FKs before delete (should already be remounted).
    session.exec(
        update(DinosaurType)
        .where(col(DinosaurType.current_revision_id).in_(delete_ids))
        .values(current_revision_id=None)
    )
    session.exec(
        update(Dinosaur)
        .where(col(Dinosaur.dinosaur_type_revision_id).in_(delete_ids))
        .values(dinosaur_type_revision_id=None)
    )
    session.flush()

    deleted = session.exec(
        delete(DinosaurTypeRevision).where(col(DinosaurTypeRevision.id).in_(delete_ids))
    )
    stats["revisions_deleted"] = int(deleted.rowcount or 0)

    # Restore current_revision_id for every type to its kept original.
    for type_id, (keep, _) in by_type.items():
        dino_type = session.get(DinosaurType, type_id)
        if dino_type is None:
            continue
        keep_id = int(keep.id)
        if dino_type.current_revision_id != keep_id:
            dino_type.current_revision_id = keep_id
            session.add(dino_type)

    session.commit()
    logger.info(
        "prune_dino_revisions: done deleted=%d occurrences_remounted=%d types_current_updated=%d",
        stats["revisions_deleted"],
        stats["occurrences_remounted"],
        stats["types_current_updated"],
    )
    return stats


def main() -> int:
    require_railway_database()
    args = _parse_args()
    with Session(engine) as session:
        prune_extra_revisions(session, apply=args.apply)
    if not args.apply:
        logger.info("Dry-run only. Re-run with --apply to persist.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
