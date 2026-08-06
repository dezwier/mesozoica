"""Load tool catalog rows from backend/data/tools.json."""

from __future__ import annotations

import json
import logging
import time
from dataclasses import dataclass, field
from pathlib import Path

from sqlmodel import Session, col, delete, select

from app.models.tool_type import ToolType

logger = logging.getLogger("tool_sync")

_BACKEND_ROOT = Path(__file__).resolve().parents[5]
DEFAULT_TOOLS_JSON = _BACKEND_ROOT / "data" / "tools.json"


@dataclass
class ToolSyncCounters:
    inserted: int = 0
    updated: int = 0
    pruned: int = 0
    skipped: int = 0


@dataclass
class ToolSyncSummary:
    total_json: int
    counters: ToolSyncCounters = field(default_factory=ToolSyncCounters)
    dry_run: bool = False
    elapsed_s: float = 0.0


def _load_tools_json(path: Path) -> list[dict]:
    raw = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(raw, list):
        raise ValueError(f"Expected JSON array in {path}")
    return raw


def _normalize_tool_names(tools: list[str] | None) -> set[str] | None:
    if not tools:
        return None
    normalized = {(name or "").strip() for name in tools}
    normalized.discard("")
    return normalized or None


def sync_tools(
    session: Session,
    *,
    dry_run: bool = False,
    prune: bool = False,
    tools: list[str] | None = None,
    json_path: Path | None = None,
) -> ToolSyncSummary:
    """Upsert tools from JSON; preserve existing main_image_url on update."""
    start = time.monotonic()
    path = json_path or DEFAULT_TOOLS_JSON
    if not path.is_file():
        raise FileNotFoundError(f"Tools JSON not found: {path}")

    entries = _load_tools_json(path)
    tool_filter = _normalize_tool_names(tools)
    counters = ToolSyncCounters()

    existing_by_name: dict[str, ToolType] = {
        row.name: row for row in session.exec(select(ToolType)).all()
    }
    seen_names: set[str] = set()

    for entry in entries:
        name = str(entry.get("name", "")).strip()
        if not name:
            counters.skipped += 1
            logger.warning("Skipping tool entry with empty name: %s", entry)
            continue
        if tool_filter is not None and name not in tool_filter:
            continue

        seen_names.add(name)
        category = str(entry.get("category", "")).strip()
        scientific_tool = str(entry.get("scientific_tool", "")).strip()
        description = str(entry.get("description", "")).strip()
        rarity = int(entry.get("rarity", 1))
        action = str(entry.get("action", "Use")).strip() or "Use"

        row = existing_by_name.get(name)
        if row is None:
            counters.inserted += 1
            logger.info('%s · INSERT', name)
            if not dry_run:
                session.add(
                    ToolType(
                        name=name,
                        category=category,
                        scientific_tool=scientific_tool,
                        description=description,
                        rarity=rarity,
                        action=action,
                    )
                )
            continue

        changed = (
            row.category != category
            or row.scientific_tool != scientific_tool
            or row.description != description
            or row.rarity != rarity
            or row.action != action
        )
        if not changed:
            counters.skipped += 1
            continue

        counters.updated += 1
        logger.info('%s · UPDATE', name)
        if not dry_run:
            row.category = category
            row.scientific_tool = scientific_tool
            row.description = description
            row.rarity = rarity
            row.action = action
            session.add(row)

    if prune:
        for name, row in existing_by_name.items():
            if tool_filter is not None and name not in tool_filter:
                continue
            if name in seen_names:
                continue
            counters.pruned += 1
            logger.info('%s · PRUNE', name)
            if not dry_run:
                session.delete(row)

    if not dry_run:
        session.commit()

    return ToolSyncSummary(
        total_json=len(entries),
        counters=counters,
        dry_run=dry_run,
        elapsed_s=time.monotonic() - start,
    )


def tool_sync_exit_code(summary: ToolSyncSummary) -> int:
    return 0
