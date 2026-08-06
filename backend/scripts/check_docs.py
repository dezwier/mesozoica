"""Validate the repository's agent documentation and local Markdown links."""

from __future__ import annotations

import re
from pathlib import Path
from urllib.parse import unquote

REPO_ROOT = Path(__file__).resolve().parents[2]
REQUIRED_DOCS = (
    "AGENTS.md",
    "README.md",
    "docs/ARCHITECTURE.md",
    "docs/README.md",
    "docs/DOMAIN.md",
    "docs/DEVELOPMENT.md",
    "docs/CONTRACTS.md",
    "docs/TESTING.md",
    "docs/OPERATIONS.md",
    "docs/PRODUCT.md",
)
EXCLUDED_PARTS = {
    ".dart_tool",
    ".git",
    ".idea",
    ".pytest_cache",
    ".venv",
    "Pods",
    "build",
    "ephemeral",
    "node_modules",
}
MARKDOWN_LINK = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")
EXTERNAL_SCHEMES = ("http://", "https://", "mailto:", "tel:", "data:")


def markdown_files() -> list[Path]:
    return sorted(
        path
        for path in REPO_ROOT.rglob("*.md")
        if not EXCLUDED_PARTS.intersection(path.relative_to(REPO_ROOT).parts)
    )


def link_target(raw: str) -> str:
    """Return a Markdown link target without an optional quoted title."""
    value = raw.strip()
    if value.startswith("<") and ">" in value:
        return value[1 : value.index(">")]
    return value.split(maxsplit=1)[0]


def main() -> int:
    errors: list[str] = []

    for relative in REQUIRED_DOCS:
        if not (REPO_ROOT / relative).is_file():
            errors.append(f"missing required documentation: {relative}")

    for document in markdown_files():
        text = document.read_text(encoding="utf-8")
        for line_number, line in enumerate(text.splitlines(), start=1):
            for match in MARKDOWN_LINK.finditer(line):
                target = link_target(match.group(1))
                if (
                    not target
                    or target.startswith("#")
                    or target.lower().startswith(EXTERNAL_SCHEMES)
                ):
                    continue
                path_text = unquote(target.split("#", 1)[0].split("?", 1)[0])
                if not path_text:
                    continue
                resolved = (document.parent / path_text).resolve()
                try:
                    resolved.relative_to(REPO_ROOT.resolve())
                except ValueError:
                    errors.append(
                        f"{document.relative_to(REPO_ROOT)}:{line_number}: "
                        f"local link escapes repository: {target}"
                    )
                    continue
                if not resolved.exists():
                    errors.append(
                        f"{document.relative_to(REPO_ROOT)}:{line_number}: "
                        f"missing local link target: {target}"
                    )

    if errors:
        print("\n".join(errors))
        return 1

    print(
        f"Documentation OK ({len(REQUIRED_DOCS)} required guides, "
        f"{len(markdown_files())} Markdown files checked)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
