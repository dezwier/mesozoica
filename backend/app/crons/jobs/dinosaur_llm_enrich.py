"""
Dinosaur LLM enrichment job.

Run manually:
  python -m app.crons.runner --job dinosaur_llm_enrich
  python -m app.crons.runner --job dinosaur_llm_enrich --overwrite
"""

from __future__ import annotations

import os

from sqlmodel import Session

from app.core.config import settings
from app.core.database import engine
from app.services.dinosaur_enrichment_service.sync import enrich_dinosaurs, enrich_exit_code


def run_enrich_job(
    *,
    dry_run: bool = False,
    overwrite: bool = False,
    max_records: int | None = None,
) -> int:
    _require_gemini_key_in_production()
    with Session(engine) as session:
        summary = enrich_dinosaurs(
            session,
            dry_run=dry_run,
            overwrite=overwrite,
            max_records=max_records,
        )
    return enrich_exit_code(summary)


def _require_gemini_key_in_production() -> None:
    env = os.getenv("ENVIRONMENT", "production").strip().lower()
    is_production = env not in ("development", "dev", "local")
    if is_production and not settings.google_gemini_api_key.strip():
        raise RuntimeError(
            "GOOGLE_GEMINI_API_KEY environment variable is required in production "
            "for dinosaur LLM enrichment."
        )
