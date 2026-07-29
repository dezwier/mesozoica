"""Move flat site-type/tool/dinosaur images into v1/ and write retroactive meta.yaml."""

from __future__ import annotations

import argparse
import logging

from app.services.curated_image_service.versions import (
    BACKFILL_RUN_DATE,
    migrate_flat_images_to_v1,
)
from app.services.image_generation_service.prompting import (
    dinosaur_image_prompt_template,
    site_type_image_prompt_template,
    tool_image_prompt_template,
)
from app.services.dinosaur_image_service.sync import (
    resolve_local_source_dir_for_sync as resolve_dinosaurs,
)
from app.services.site_type_image_service.sync import resolve_local_source_dir_for_sync as resolve_site_types
from app.services.tool_image_service.sync import resolve_local_source_dir_for_sync as resolve_tools

logger = logging.getLogger(__name__)


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Migrate flat images/site-types, images/tools, and images/dinosaurs "
            "files into v1/ and write meta.yaml (prompt + backfill run_date)."
        )
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview moves without writing files.",
    )
    parser.add_argument(
        "--kind",
        choices=("all", "site-types", "tools", "dinosaurs"),
        default="all",
        help="Which image root to migrate (default: all).",
    )
    return parser.parse_args()


def run_migrate(*, dry_run: bool = False, kind: str = "all") -> int:
    targets: list[tuple[str, object, str]] = []
    if kind in ("all", "site-types"):
        targets.append(
            ("site-types", resolve_site_types(), site_type_image_prompt_template())
        )
    if kind in ("all", "tools"):
        targets.append(("tools", resolve_tools(), tool_image_prompt_template()))
    if kind in ("all", "dinosaurs"):
        targets.append(
            ("dinosaurs", resolve_dinosaurs(), dinosaur_image_prompt_template())
        )

    for label, root, prompt in targets:
        logger.info("=== migrate %s (%s) ===", label, root)
        summary = migrate_flat_images_to_v1(
            root,  # type: ignore[arg-type]
            default_prompt=prompt,
            backfill_run_date=BACKFILL_RUN_DATE,
            dry_run=dry_run,
        )
        logger.info(
            "%s: moved=%d skipped=%d run_date=%s",
            label,
            summary["moved"],
            summary["skipped"],
            BACKFILL_RUN_DATE.isoformat(),
        )
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
