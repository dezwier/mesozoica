"""
Procedural field site generation job.

Run manually:
  python -m app.crons.runner --job field_site_generate
  python -m app.crons.runner --job field_site_generate --dry-run --max-items 10
  python -m app.crons.runner --job field_site_generate --refresh --max-items 100
"""

from __future__ import annotations

from sqlmodel import Session

from app.core.database import engine
from app.services.site_service.field_generate import (
    config_from_params,
    field_site_generate_exit_code,
    generate_field_sites,
)


def run_generate_job(**params) -> int:
    config = config_from_params(params)
    dry_run = bool(params.get("dry_run", False))
    with Session(engine) as session:
        summary = generate_field_sites(session, config=config, dry_run=dry_run)
    return field_site_generate_exit_code(summary)
