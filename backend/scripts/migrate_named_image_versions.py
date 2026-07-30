"""Rename legacy v1/v2 image folders to named versions; migrate flat fossils."""

from __future__ import annotations

import argparse
import logging

from app.services.curated_image_service.versions import (
    BACKFILL_RUN_DATE,
    ORIGINAL_VERSION,
    migrate_flat_images_to_version,
    rename_legacy_version_folders,
)
from app.services.dinosaur_image_service.sync import (
    resolve_local_source_dir_for_sync as resolve_dinosaurs,
)
from app.services.fossil_image_service.sync import (
    resolve_local_source_dir_for_sync as resolve_fossils,
)
from app.services.image_generation_service.prompting import (
    dinosaur_image_prompt_template,
    fossil_image_prompt_template,
    site_type_image_prompt_template,
    tool_image_prompt_template,
)
from app.services.site_type_image_service.sync import (
    resolve_local_source_dir_for_sync as resolve_site_types,
)
from app.services.tool_image_service.sync import (
    resolve_local_source_dir_for_sync as resolve_tools,
)

logger = logging.getLogger(__name__)


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Rename images/*/v1 -> Original, v2 -> Summer 26; "
            "move flat fossil images into Original/ with meta.yaml."
        )
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview renames/moves without writing files.",
    )
    parser.add_argument(
        "--kind",
        choices=("all", "site-types", "tools", "dinosaurs", "fossils"),
        default="all",
        help="Which image root to migrate (default: all).",
    )
    return parser.parse_args()


def run_migrate(*, dry_run: bool = False, kind: str = "all") -> int:
    rename_targets: list[tuple[str, object]] = []
    if kind in ("all", "site-types"):
        rename_targets.append(("site-types", resolve_site_types()))
    if kind in ("all", "tools"):
        rename_targets.append(("tools", resolve_tools()))
    if kind in ("all", "dinosaurs"):
        rename_targets.append(("dinosaurs", resolve_dinosaurs()))

    for label, root in rename_targets:
        logger.info("=== rename legacy versions %s (%s) ===", label, root)
        summary = rename_legacy_version_folders(root, dry_run=dry_run)  # type: ignore[arg-type]
        logger.info(
            "%s: renamed=%d skipped=%d",
            label,
            summary["renamed"],
            summary["skipped"],
        )

    if kind in ("all", "fossils"):
        root = resolve_fossils()
        logger.info("=== migrate flat fossils (%s) ===", root)
        summary = migrate_flat_images_to_version(
            root,  # type: ignore[arg-type]
            version_name=ORIGINAL_VERSION,
            default_prompt=fossil_image_prompt_template(),
            backfill_run_date=BACKFILL_RUN_DATE,
            dry_run=dry_run,
        )
        logger.info(
            "fossils: moved=%d skipped=%d run_date=%s",
            summary["moved"],
            summary["skipped"],
            BACKFILL_RUN_DATE.isoformat(),
        )

    # Also ensure prompts exist on renamed folders (no-op if meta already present).
    ensure_prompts: list[tuple[str, object, str]] = []
    if kind in ("all", "site-types"):
        ensure_prompts.append(
            ("site-types", resolve_site_types(), site_type_image_prompt_template())
        )
    if kind in ("all", "tools"):
        ensure_prompts.append(("tools", resolve_tools(), tool_image_prompt_template()))
    if kind in ("all", "dinosaurs"):
        ensure_prompts.append(
            ("dinosaurs", resolve_dinosaurs(), dinosaur_image_prompt_template())
        )
    from app.services.curated_image_service.versions import (
        ensure_version_meta,
        load_image_versions,
    )

    for label, root, prompt in ensure_prompts:
        for version in load_image_versions(root):  # type: ignore[arg-type]
            if dry_run:
                continue
            ensure_version_meta(
                version.path,
                default_prompt=prompt,
                preserve_existing_run_date=True,
            )
            logger.info("%s/%s: meta ensured", label, version.name)

    return 0


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    args = _parse_args()
    try:
        raise SystemExit(run_migrate(dry_run=args.dry_run, kind=args.kind))
    except Exception as exc:
        logger.error("%s", exc)
        raise SystemExit(1) from exc


if __name__ == "__main__":
    main()
