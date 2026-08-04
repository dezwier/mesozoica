"""Copy run_date from images/*/meta.yaml into app/data/curated_version_meta/."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import yaml

_BACKEND_DIR = Path(__file__).resolve().parents[1]
_REPO_ROOT = _BACKEND_DIR.parent
_IMAGES_ROOT = _REPO_ROOT / "images"
_BUNDLED_ROOT = _BACKEND_DIR / "app" / "data" / "curated_version_meta"

_KINDS = ("site-types", "dinosaurs", "tools", "fossils")


def _run_date_from_meta(path: Path) -> str | None:
    data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    value = data.get("run_date")
    if value is None:
        return None
    return str(value).strip() or None


def sync(*, dry_run: bool = False) -> int:
    written = 0
    for kind in _KINDS:
        kind_dir = _IMAGES_ROOT / kind
        if not kind_dir.is_dir():
            continue
        for version_dir in sorted(kind_dir.iterdir(), key=lambda p: p.name.lower()):
            if not version_dir.is_dir():
                continue
            meta = version_dir / "meta.yaml"
            if not meta.is_file():
                continue
            run_date = _run_date_from_meta(meta)
            if run_date is None:
                print(f"skip {kind}/{version_dir.name}: no run_date", file=sys.stderr)
                continue
            dest_dir = _BUNDLED_ROOT / kind / version_dir.name
            dest = dest_dir / "meta.yaml"
            payload = yaml.safe_dump({"run_date": run_date}, sort_keys=False)
            if dry_run:
                print(f"would write {dest.relative_to(_BACKEND_DIR)} run_date={run_date}")
            else:
                dest_dir.mkdir(parents=True, exist_ok=True)
                dest.write_text(payload, encoding="utf-8")
                print(f"wrote {dest.relative_to(_BACKEND_DIR)} run_date={run_date}")
            written += 1
    return written


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print actions without writing files",
    )
    args = parser.parse_args()
    count = sync(dry_run=args.dry_run)
    print(f"synced={count} dry_run={args.dry_run}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
