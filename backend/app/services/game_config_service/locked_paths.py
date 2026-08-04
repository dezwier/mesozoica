"""Enforcement of the non-editable regions of the control board."""

from __future__ import annotations

from typing import Any, Iterator

from app.core.game_config import RawDocuments
from app.core.game_config_docs import LOCKED_PATHS

_MISSING = object()


class GameConfigLocked(ValueError):
    """A write touched a path that is not admin-editable."""


def _expand(pattern: str, documents: RawDocuments) -> Iterator[tuple[str, ...]]:
    """Expand a '*' pattern against the documents into concrete paths."""
    frontier: list[tuple[tuple[str, ...], Any]] = [((), documents)]
    for segment in pattern.split("/"):
        nxt: list[tuple[tuple[str, ...], Any]] = []
        for prefix, node in frontier:
            if segment == "*":
                if isinstance(node, dict):
                    nxt.extend(
                        ((*prefix, str(key)), value) for key, value in node.items()
                    )
                continue
            if isinstance(node, dict) and segment in node:
                nxt.append(((*prefix, segment), node[segment]))
        frontier = nxt
    for path, _ in frontier:
        yield path


def deep_get(documents: Any, path: tuple[str, ...]) -> Any:
    """Value at ``path``, or a sentinel when any segment is absent."""
    node: Any = documents
    for segment in path:
        if not isinstance(node, dict) or segment not in node:
            return _MISSING
        node = node[segment]
    return node


def locked_path_violations(
    candidate: RawDocuments, active: RawDocuments
) -> list[str]:
    """Locked paths whose value differs between ``candidate`` and ``active``.

    Expanded against both sides so that adding or removing a locked subtree
    (e.g. a new tool's ``stats_explanation``) is caught too.
    """
    violations: list[str] = []
    for pattern in LOCKED_PATHS:
        paths = set(_expand(pattern, candidate)) | set(_expand(pattern, active))
        if not paths:
            # Pattern matched nothing on either side: compare literally so a
            # wholly removed locked document is still rejected.
            literal = tuple(pattern.split("/"))
            if "*" not in literal and deep_get(candidate, literal) != deep_get(
                active, literal
            ):
                violations.append(pattern)
            continue
        for path in sorted(paths):
            if deep_get(candidate, path) != deep_get(active, path):
                violations.append("/".join(path))
    return violations


def assert_locked_paths_unchanged(
    candidate: RawDocuments, active: RawDocuments
) -> None:
    violations = locked_path_violations(candidate, active)
    if violations:
        raise GameConfigLocked(
            "These game config paths are not editable: " + ", ".join(violations)
        )
