"""Rename legacy numeric site-type image files to period_rocktype stems."""

from __future__ import annotations

import argparse
import logging
import sys

from sqlmodel import Session, select

from app.core.database import engine
from app.crons.railway_guard import require_railway_database
from app.models.site_type import SiteType
from app.services.curated_image_service.common import ALLOWED_IMAGE_EXTENSIONS
from app.services.site_type_image_service.sync import (
    resolve_local_source_dir_for_sync,
    site_type_image_key,
    _legacy_order_index,
)

logger = logging.getLogger(__name__)


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Rename images/site-types/<id>.<ext> files to <period>_<rock_type>.<ext> "
            "using the current site_type table."
        )
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Log planned renames without changing files.",
    )
    return parser.parse_args()


def run_rename(*, dry_run: bool = False) -> int:
    require_railway_database()

    source_dir = resolve_local_source_dir_for_sync()
    renamed = 0
    skipped = 0
    missing = 0

    with Session(engine) as session:
        site_types = list(session.exec(select(SiteType)).all())
        by_legacy_order = _legacy_order_index(site_types)

        for row in site_types:
            if row.id is None:
                continue
            key = site_type_image_key(period=row.period, rock_type=row.rock_type)
            for ext in ALLOWED_IMAGE_EXTENSIONS:
                legacy_path = source_dir / f"{row.id}{ext}"
                target_path = source_dir / f"{key}{ext}"
                if not legacy_path.is_file():
                    continue
                if target_path.is_file():
                    logger.info(
                        "Skipping %s (target already exists: %s)",
                        legacy_path.name,
                        target_path.name,
                    )
                    skipped += 1
                    continue
                logger.info(
                    "%s %s -> %s",
                    "Would rename" if dry_run else "Renaming",
                    legacy_path.name,
                    target_path.name,
                )
                if not dry_run:
                    legacy_path.rename(target_path)
                renamed += 1

        for legacy_index, row in by_legacy_order.items():
            if row.id is None:
                continue
            key = site_type_image_key(period=row.period, rock_type=row.rock_type)
            for ext in ALLOWED_IMAGE_EXTENSIONS:
                legacy_path = source_dir / f"{legacy_index}{ext}"
                target_path = source_dir / f"{key}{ext}"
                if not legacy_path.is_file():
                    continue
                if target_path.is_file():
                    logger.info(
                        "Skipping %s (target already exists: %s)",
                        legacy_path.name,
                        target_path.name,
                    )
                    skipped += 1
                    continue
                logger.info(
                    "%s %s -> %s (legacy sorted-order #%d)",
                    "Would rename" if dry_run else "Renaming",
                    legacy_path.name,
                    target_path.name,
                    legacy_index,
                )
                if not dry_run:
                    legacy_path.rename(target_path)
                renamed += 1

        for row in site_types:
            if row.id is None:
                continue
            key = site_type_image_key(period=row.period, rock_type=row.rock_type)
            if any((source_dir / f"{key}{ext}").is_file() for ext in ALLOWED_IMAGE_EXTENSIONS):
                continue
            if any((source_dir / f"{row.id}{ext}").is_file() for ext in ALLOWED_IMAGE_EXTENSIONS):
                continue
            missing += 1

    logger.info(
        "Summary: %d renamed, %d skipped, %d site_types still without local image",
        renamed,
        skipped,
        missing,
    )
    return 0


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    args = _parse_args()
    try:
        raise SystemExit(run_rename(dry_run=args.dry_run))
    except Exception as exc:
        logger.error("%s", exc)
        raise SystemExit(1) from exc


if __name__ == "__main__":
    main()
