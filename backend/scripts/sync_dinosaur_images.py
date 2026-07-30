"""Upload curated dinosaur card images to Railway and update main_image_url."""

from __future__ import annotations

import argparse
import logging

from sqlmodel import Session, select

from app.core.config import settings
from app.core.database import engine
from app.crons.railway_guard import require_railway_database
from app.models.dinosaur_type import DinosaurType
from app.services.curated_image_service.common import needs_curated_image_resync
from app.services.curated_image_service.sync_prune import sync_meta_and_prune_remote
from app.services.dinosaur_image_service.sync import (
    CURATED_MEDIA_PATH,
    build_curated_image_url,
    catalog_relative_path_for_dinosaur,
    collect_versioned_matches,
    file_content_version,
    is_curated_image_url,
    latest_relative_path_for_dinosaur,
    resolve_local_source_dir_for_sync,
    resolve_public_base_url_for_sync,
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

    with Session(engine) as session:
        dinosaurs = list(session.exec(select(DinosaurType)).all())
        name_set = {row.name for row in dinosaurs}
        matched, unmatched_files = collect_versioned_matches(name_set)
        if not matched:
            logger.warning("No image files found under version folders in %s", source_dir)

        uploaded = 0
        updated = 0
        cleared = 0
        skipped = 0
        matched_names = {match.dinosaur_name for match in matched}

        for match in matched:
            row = next((d for d in dinosaurs if d.name == match.dinosaur_name), None)
            latest = latest_relative_path_for_dinosaur(
                dinosaur_name=match.dinosaur_name,
                root=source_dir,
            )
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
                skipped += 1
                continue

            logger.info(
                "%s %s",
                "Would upload" if dry_run else "Upload",
                match.relative_path,
            )
            if not dry_run:
                upload_file_to_railway(
                    local_path=match.path,
                    remote_filename=match.relative_path,
                    public_base_url=public_base_url,
                    sync_secret=sync_secret,
                )
            uploaded += 1

        for row in dinosaurs:
            if row.name not in matched_names:
                if is_curated_image_url(row.main_image_url):
                    if not dry_run:
                        row.main_image_url = None
                        session.add(row)
                    cleared += 1
                continue

            latest = catalog_relative_path_for_dinosaur(
                dinosaur_name=row.name,
                root=source_dir,
            )
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
            if not dry_run:
                row.main_image_url = public_url
                session.add(row)
            updated += 1

        if not dry_run:
            session.commit()

        if unmatched_files:
            logger.warning(
                "Unmatched local files (no dinosaur.name): %s",
                ", ".join(path.name for path in unmatched_files),
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

    sync_meta_and_prune_remote(
        root=source_dir,
        public_base_url=public_base_url,
        sync_secret=sync_secret,
        admin_upload_path="/api/v1/admin/dinosaur-images",
        sync_header_name="X-Dinosaur-Image-Sync-Key",
        sync_secret_env_var="DINOSAUR_IMAGE_SYNC_SECRET",
        upload_file=upload_file_to_railway,
        dry_run=dry_run,
    )

    return 0


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    logging.getLogger("httpx").setLevel(logging.WARNING)
    args = _parse_args()
    try:
        raise SystemExit(run_sync(dry_run=args.dry_run, overwrite=args.overwrite))
    except Exception as exc:
        logger.error("%s", exc)
        raise SystemExit(1) from exc


if __name__ == "__main__":
    main()
