"""Upload curated site-type card images to Railway and update main_image_url."""

from __future__ import annotations

import argparse
import logging
import sys

from sqlmodel import Session, select

from app.core.config import settings
from app.core.database import engine
from app.crons.railway_guard import require_railway_database
from app.models.site_type import SiteType
from app.services.dinosaur_image_service.sync import file_content_version
from app.services.site_type_image_service.sync import (
    build_curated_image_url,
    match_image_files,
    remote_image_exists,
    resolve_local_source_dir_for_sync,
    resolve_public_base_url_for_sync,
    scan_local_image_files,
    upload_file_to_railway,
)

logger = logging.getLogger(__name__)


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Sync curated site-type card images to Railway volume and database."
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview matches without uploading files or updating the database.",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Replace images already on Railway. Default: upload only missing images.",
    )
    return parser.parse_args()


def run_sync(*, dry_run: bool = False, overwrite: bool = False) -> int:
    if not dry_run:
        require_railway_database()

    source_dir = resolve_local_source_dir_for_sync()
    public_base_url = resolve_public_base_url_for_sync()
    sync_secret = settings.site_type_image_sync_secret

    image_files = scan_local_image_files(source_dir)
    if not image_files:
        logger.warning("No image files found in %s", source_dir)
        return 0

    with Session(engine) as session:
        site_types = session.exec(select(SiteType)).all()
        id_set = {row.id for row in site_types if row.id is not None}
        matched, unmatched_files = match_image_files(image_files, id_set)

        uploaded = 0
        updated = 0
        skipped = 0
        for match in matched:
            if not overwrite and remote_image_exists(
                public_base_url=public_base_url,
                filename=match.filename,
            ):
                logger.info("Skipping %s (already on Railway)", match.filename)
                skipped += 1
                continue

            public_url = build_curated_image_url(
                public_base_url,
                match.filename,
                version=file_content_version(match.path),
            )
            logger.info(
                "%s %s -> %s",
                "Would sync" if dry_run else "Syncing",
                match.filename,
                public_url,
            )
            if not dry_run:
                upload_file_to_railway(
                    local_path=match.path,
                    remote_filename=match.filename,
                    public_base_url=public_base_url,
                    sync_secret=sync_secret,
                )
                uploaded += 1

                row = session.get(SiteType, match.site_type_id)
                if row is not None:
                    row.main_image_url = public_url
                    session.add(row)
                    updated += 1

        if not dry_run:
            session.commit()

        site_types_without_images = sorted(
            site_type_id
            for site_type_id in id_set
            if not any(m.site_type_id == site_type_id for m in matched)
        )
        if unmatched_files:
            logger.warning(
                "Unmatched local files (no site_type.id): %s",
                ", ".join(path.name for path in unmatched_files),
            )
        if site_types_without_images:
            logger.info(
                "Site types without curated images: %d (first 10: %s)",
                len(site_types_without_images),
                ", ".join(str(value) for value in site_types_without_images[:10]),
            )

        logger.info(
            "Summary: %d matched, %d uploaded, %d db_updated, %d skipped, %d unmatched files",
            len(matched),
            uploaded,
            updated,
            skipped,
            len(unmatched_files),
        )

    return 0


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    args = _parse_args()
    try:
        raise SystemExit(run_sync(dry_run=args.dry_run, overwrite=args.overwrite))
    except Exception as exc:
        logger.error("%s", exc)
        raise SystemExit(1) from exc


if __name__ == "__main__":
    main()
