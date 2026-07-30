"""Upload curated fossil card images to Railway and update main_image_url."""

from __future__ import annotations

import argparse
import logging
import sys

from sqlmodel import Session, select

from app.core.config import settings
from app.core.database import engine
from app.crons.railway_guard import require_railway_database
from app.models.fossil import Fossil
from app.services.curated_image_service.common import needs_curated_image_resync
from app.services.fossil_image_service.sync import (
    CURATED_MEDIA_PATH,
    build_curated_image_url,
    file_content_version,
    is_curated_image_url,
    latest_relative_path_for_fossil,
    match_image_files,
    resolve_local_source_dir_for_sync,
    resolve_public_base_url_for_sync,
    scan_fossil_image_files,
    upload_file_to_railway,
)

logger = logging.getLogger(__name__)


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Sync curated fossil card images to Railway volume and database."
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
    sync_secret = settings.fossil_image_sync_secret

    image_files = scan_fossil_image_files(source_dir)
    if not image_files:
        logger.warning("No image files found in %s", source_dir)

    with Session(engine) as session:
        fossils = session.exec(select(Fossil)).all()
        id_set = {row.id for row in fossils}
        if image_files:
            matched, unmatched_files = match_image_files(image_files, id_set)
        else:
            matched, unmatched_files = [], []

        uploaded = 0
        updated = 0
        cleared = 0
        skipped = 0
        matched_ids = {match.fossil_id for match in matched}

        for match in matched:
            row = session.get(Fossil, match.fossil_id)
            latest = latest_relative_path_for_fossil(source_dir, match.fossil_id)
            is_latest = latest is not None and latest[0] == match.relative_path
            main_image_url = row.main_image_url if row is not None and is_latest else None
            if not needs_curated_image_resync(
                overwrite=overwrite,
                local_path=match.path,
                main_image_url=main_image_url,
                public_base_url=public_base_url,
                filename=match.relative_path,
                curated_media_path=CURATED_MEDIA_PATH,
            ):
                logger.info("Skipping %s (already synced)", match.relative_path)
                skipped += 1
                continue

            public_url = build_curated_image_url(
                public_base_url,
                match.relative_path,
                version=file_content_version(match.path),
            )
            logger.info(
                "%s %s -> %s",
                "Would sync" if dry_run else "Syncing",
                match.relative_path,
                public_url,
            )
            if not dry_run:
                upload_file_to_railway(
                    local_path=match.path,
                    remote_filename=match.relative_path,
                    public_base_url=public_base_url,
                    sync_secret=sync_secret,
                )
                uploaded += 1

        for row in fossils:
            if row.id not in matched_ids:
                if is_curated_image_url(row.main_image_url):
                    logger.info(
                        "%s fossil %d main_image_url (no local image in %s)",
                        "Would clear" if dry_run else "Clearing",
                        row.id,
                        source_dir,
                    )
                    if not dry_run:
                        row.main_image_url = None
                        session.add(row)
                    cleared += 1
                continue

            latest = latest_relative_path_for_fossil(source_dir, int(row.id))
            if latest is None:
                continue
            relative_path, local_path = latest
            public_url = build_curated_image_url(
                public_base_url,
                relative_path,
                version=file_content_version(local_path),
            )
            if row.main_image_url == public_url:
                continue
            logger.info(
                "%s fossil %d main_image_url -> %s",
                "Would set" if dry_run else "Setting",
                row.id,
                public_url,
            )
            if not dry_run:
                row.main_image_url = public_url
                session.add(row)
                updated += 1

        if not dry_run:
            session.commit()

        fossils_without_images = sorted(
            fossil_id for fossil_id in id_set if fossil_id not in matched_ids
        )
        if unmatched_files:
            logger.warning(
                "Unmatched local files (no fossil.id): %s",
                ", ".join(path.name for path in unmatched_files),
            )
        if fossils_without_images:
            logger.info(
                "Fossils without curated images: %d (first 10: %s)",
                len(fossils_without_images),
                ", ".join(str(value) for value in fossils_without_images[:10]),
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
