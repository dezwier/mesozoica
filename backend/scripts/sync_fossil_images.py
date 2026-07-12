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
from app.services.fossil_image_service.sync import (
    build_curated_image_url,
    match_image_files,
    resolve_local_source_dir_for_sync,
    resolve_public_base_url_for_sync,
    scan_local_image_files,
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
    return parser.parse_args()


def run_sync(*, dry_run: bool = False) -> int:
    if not dry_run:
        require_railway_database()

    source_dir = resolve_local_source_dir_for_sync()
    public_base_url = resolve_public_base_url_for_sync()
    sync_secret = settings.fossil_image_sync_secret

    image_files = scan_local_image_files(source_dir)
    if not image_files:
        logger.warning("No image files found in %s", source_dir)
        return 0

    with Session(engine) as session:
        fossils = session.exec(select(Fossil)).all()
        id_set = {row.id for row in fossils}
        matched, unmatched_files = match_image_files(image_files, id_set)

        uploaded = 0
        updated = 0
        for match in matched:
            public_url = build_curated_image_url(public_base_url, match.filename)
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

                row = session.get(Fossil, match.fossil_id)
                if row is not None:
                    row.main_image_url = public_url
                    session.add(row)
                    updated += 1

        if not dry_run:
            session.commit()

        fossils_without_images = sorted(
            fossil_id for fossil_id in id_set if not any(m.fossil_id == fossil_id for m in matched)
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
            "Summary: %d matched, %d uploaded, %d db_updated, %d unmatched files",
            len(matched),
            uploaded,
            updated,
            len(unmatched_files),
        )

    return 0


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    args = _parse_args()
    try:
        raise SystemExit(run_sync(dry_run=args.dry_run))
    except Exception as exc:
        logger.error("%s", exc)
        raise SystemExit(1) from exc


if __name__ == "__main__":
    main()
