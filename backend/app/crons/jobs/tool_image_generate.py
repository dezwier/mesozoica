"""
Tool card image generation job.

Run manually:
  python -m app.crons.runner --job tool_image_generate
  python -m app.crons.runner --job tool_image_generate --max-items 5
  python -m app.crons.runner --job tool_image_generate --tools "Orbit Survey" --dry-run
"""

from __future__ import annotations

import os

from sqlmodel import Session

from app.core.config import settings
from app.core.database import engine
from app.services.tool_image_generation_service.generate import (
    generate_exit_code,
    generate_tool_images,
)


def run_generate_job(
    *,
    dry_run: bool = False,
    max_items: int | None = None,
    tools: list[str] | None = None,
) -> int:
    _require_gemini_key_in_production()
    with Session(engine) as session:
        summary = generate_tool_images(
            session,
            dry_run=dry_run,
            max_items=max_items,
            tools=tools,
        )
    return generate_exit_code(summary)


def _require_gemini_key_in_production() -> None:
    env = os.getenv("ENVIRONMENT", "production").strip().lower()
    is_production = env not in ("development", "dev", "local")
    if is_production and not settings.google_gemini_api_key.strip():
        raise RuntimeError(
            "GOOGLE_GEMINI_API_KEY environment variable is required in production "
            "for tool image generation."
        )
