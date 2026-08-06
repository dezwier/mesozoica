"""
Dinosaur card image generation job. Feature-owned implementation.

Run manually:
  python -m app.crons.runner --job dinosaur_image_generate --version Original
  python -m app.crons.runner --job dinosaur_image_generate --version "Summer 26" --max-items 5
  python -m app.crons.runner --job dinosaur_image_generate --version Original --dinos Tyrannosaurus --dry-run
"""

from __future__ import annotations

import os

from sqlmodel import Session

from app.core.config import settings
from app.core.database import engine
from app.features.media.application.dinosaur_generation.generate import (
    generate_dinosaur_images,
    generate_exit_code,
)


def run_generate_job(
    *,
    dry_run: bool = False,
    max_items: int | None = None,
    dinos: list[str] | None = None,
    version: str,
) -> int:
    _require_gemini_key_in_production()
    with Session(engine) as session:
        summary = generate_dinosaur_images(
            session,
            dry_run=dry_run,
            max_items=max_items,
            dinos=dinos,
            version=version,
        )
    return generate_exit_code(summary)


def _require_gemini_key_in_production() -> None:
    env = os.getenv("ENVIRONMENT", "production").strip().lower()
    is_production = env not in ("development", "dev", "local")
    if is_production and not settings.google_gemini_api_key.strip():
        raise RuntimeError(
            "GOOGLE_GEMINI_API_KEY environment variable is required in production "
            "for dinosaur image generation."
        )
