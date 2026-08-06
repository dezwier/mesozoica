"""Advisory report for source files that remain decomposition candidates."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOTS = (ROOT / "backend" / "app", ROOT / "flutter" / "lib")
LIMIT = 500


def main() -> None:
    rows: list[tuple[int, Path]] = []
    for source_root in SOURCE_ROOTS:
        for suffix in ("*.py", "*.dart"):
            for path in source_root.rglob(suffix):
                count = sum(1 for _ in path.open(encoding="utf-8"))
                if count > LIMIT:
                    rows.append((count, path.relative_to(ROOT)))
    for count, path in sorted(rows, reverse=True):
        print(f"{count:5d}  {path}")
    print(f"{len(rows)} source files exceed {LIMIT} lines (advisory)")


if __name__ == "__main__":
    main()

