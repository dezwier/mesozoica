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
from app.services.curated_image_service.common import needs_curated_image_resync
from app.services.curated_image_service.sync_prune import sync_meta_and_prune_remote
from app.services.curated_image_service.versions import load_image_versions
from app.services.site_type_image_service.sync import (
    CURATED_MEDIA_PATH,
    build_curated_image_url,
    collect_versioned_matches,
    file_content_version,
    is_curated_image_url,
    latest_relative_path_for_site_type,
    resolve_local_source_dir_for_sync,
    resolve_public_base_url_for_sync,
    site_type_image_key,
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

    with Session(engine) as session:
        site_types = list(session.exec(select(SiteType)).all())
        matched, unmatched_files = collect_versioned_matches(site_types)
        if not matched:
            logger.warning("No image files found under version folders in %s", source_dir)

        uploaded = 0
        updated = 0
        cleared = 0
        skipped = 0
        matched_keys = {
            site_type_image_key(period=match.period, rock_type=match.rock_type)
            for match in matched
        }

        # Upload every versioned file.
        for match in matched:
            row = session.get(SiteType, match.site_type_id)
            # Only compare content hash against DB URL when this file is the latest
            # for the type; otherwise just check remote existence.
            latest = latest_relative_path_for_site_type(
                period=match.period,
                rock_type=match.rock_type,
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

        # Point main_image_url at the latest version by run_date.
        for row in site_types:
            key = site_type_image_key(period=row.period, rock_type=row.rock_type)
            if key not in matched_keys:
                if is_curated_image_url(row.main_image_url):
                    logger.info(
                        "%s site_type %s/%s main_image_url (no local image in %s)",
                        "Would clear" if dry_run else "Clearing",
                        row.period,
                        row.rock_type,
                        source_dir,
                    )
                    if not dry_run:
                        row.main_image_url = None
                        session.add(row)
                    cleared += 1
                continue

            latest = latest_relative_path_for_site_type(
                period=row.period,
                rock_type=row.rock_type,
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
            logger.info(
                "%s site_type %s/%s main_image_url -> %s",
                "Would set" if dry_run else "Setting",
                row.period,
                row.rock_type,
                public_url,
            )
            if not dry_run:
                row.main_image_url = public_url
                session.add(row)
                updated += 1

        if not dry_run:
            session.commit()

        site_types_without_images = sorted(
            site_type_image_key(period=row.period, rock_type=row.rock_type)
            for row in site_types
            if site_type_image_key(period=row.period, rock_type=row.rock_type)
            not in matched_keys
        )
        if unmatched_files:
            logger.warning(
                "Unmatched local files (no site_type match): %s",
                ", ".join(path.name for path in unmatched_files),
            )
        versions = load_image_versions(source_dir)
        logger.info(
            "Versions: %s",
            ", ".join(
                f"{v.name}(run_date={v.run_date.isoformat() if v.run_date else 'none'})"
                for v in versions
            )
            or "none",
        )
        if site_types_without_images:
            logger.info(
                "Site types without curated images: %d (first 10: %s)",
                len(site_types_without_images),
                ", ".join(site_types_without_images[:10]),
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
        admin_upload_path="/api/v1/admin/site-type-images",
        sync_header_name="X-Site-Type-Image-Sync-Key",
        sync_secret_env_var="SITE_TYPE_IMAGE_SYNC_SECRET",
        upload_file=upload_file_to_railway,
        dry_run=dry_run,
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
