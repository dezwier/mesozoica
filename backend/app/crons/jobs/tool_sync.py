"""
Tool catalog sync job.

Run manually:
  python -m app.crons.runner --job tool_sync
  python -m app.crons.runner --job tool_sync --dry-run
  python -m app.crons.runner --job tool_sync --tools "Orbit Survey" "Geo Hammer"
"""

from __future__ import annotations

from sqlmodel import Session

from app.core.database import engine
from app.services.tool_service.sync import sync_tools, tool_sync_exit_code


def run_sync_job(
    *,
    dry_run: bool = False,
    prune: bool = False,
    tools: list[str] | None = None,
) -> int:
    with Session(engine) as session:
        summary = sync_tools(session, dry_run=dry_run, prune=prune, tools=tools)
    return tool_sync_exit_code(summary)
