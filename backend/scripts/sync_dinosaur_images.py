"""Upload curated dinosaur card images to Railway and update main_image_url."""

from __future__ import annotations

import argparse
import logging
import sys

from sqlmodel import Session, select

from app.core.config import settings
from app.core.database import engine
from app.crons.railway_guard import require_railway_database
from app.models.dinosaur import Dinosaur
from app.services.curated_image_service.common import needs_curated_image_resync
from app.services.dinosaur_image_service.sync import (
    CURATED_MEDIA_PATH,
    build_curated_image_url,
    file_content_version,
    is_curated_image_url,
    match_image_files,
    resolve_local_source_dir_for_sync,
    resolve_public_base_url_for_sync,
    scan_local_image_files,
    upload_file_to_railway,
)

logger = logging.getLogger(__name__)


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Sync curated dinosaur card images to Railway volume and database."
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
    sync_secret = settings.dinosaur_image_sync_secret

    image_files = scan_local_image_files(source_dir)
    if not image_files:
        logger.warning("No image files found in %s", source_dir)

    with Session(engine) as session:
        dinosaurs = session.exec(select(Dinosaur)).all()
        name_set = {row.name for row in dinosaurs}
        if image_files:
            matched, unmatched_files = match_image_files(image_files, name_set)
        else:
            matched, unmatched_files = [], []

        uploaded = 0
        updated = 0
        cleared = 0
        skipped = 0
        matched_names = {match.dinosaur_name for match in matched}
        for match in matched:
            row = session.exec(
                select(Dinosaur).where(Dinosaur.name == match.dinosaur_name)
            ).first()
            main_image_url = row.main_image_url if row is not None else None
            if not needs_curated_image_resync(
                overwrite=overwrite,
                local_path=match.path,
                main_image_url=main_image_url,
                public_base_url=public_base_url,
                filename=match.filename,
                curated_media_path=CURATED_MEDIA_PATH,
            ):
                logger.info("Skipping %s (already synced)", match.filename)
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

                if row is not None:
                    row.main_image_url = public_url
                    session.add(row)
                    updated += 1

        for row in dinosaurs:
            if row.name in matched_names:
                continue
            if not is_curated_image_url(row.main_image_url):
                continue
            logger.info(
                "%s dinosaur %s main_image_url (no local image in %s)",
                "Would clear" if dry_run else "Clearing",
                row.name,
                source_dir,
            )
            if not dry_run:
                row.main_image_url = None
                session.add(row)
            cleared += 1

        if not dry_run:
            session.commit()

        dinosaurs_without_images = sorted(name for name in name_set if name not in matched_names)
        if unmatched_files:
            logger.warning(
                "Unmatched local files (no dinosaur.name): %s",
                ", ".join(path.name for path in unmatched_files),
            )
        if dinosaurs_without_images:
            logger.info(
                "Dinosaurs without curated images: %d (first 10: %s)",
                len(dinosaurs_without_images),
                ", ".join(dinosaurs_without_images[:10]),
            )

        logger.info(
            "Summary: %d matched, %d uploaded, %d db_updated, %d cleared, %d skipped, %d unmatched files",
            len(matched),
            uploaded,
            updated,
            cleared,
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
