"""Acquire resumable Wikipedia and OpenAlex snapshots for dinosaur knowledge."""

from __future__ import annotations

from contextlib import ExitStack

from sqlmodel import Session

from app.core.config import settings
from app.core.database import engine
from app.features.ingestion.application.knowledge import acquire_dinosaur_knowledge
from app.features.specimens.public import list_dinosaur_knowledge_subjects
from mesozoica_ai.sources import OpenAlexSource, WikipediaSource


def run_acquire_job(
    *,
    dry_run: bool = False,
    overwrite: bool = False,
    max_items: int | None = None,
    dinos: list[str] | None = None,
    sources: list[str] | None = None,
) -> int:
    requested = sources or ["wikipedia", "openalex"]
    with ExitStack() as stack:
        wikipedia = (
            stack.enter_context(WikipediaSource(user_agent=settings.wikipedia_user_agent))
            if "wikipedia" in requested
            else None
        )
        openalex = None
        if "openalex" in requested:
            if not settings.openalex_api_key and not dry_run:
                raise RuntimeError("OPENALEX_API_KEY is required for OpenAlex acquisition")
            if settings.openalex_api_key:
                openalex = stack.enter_context(OpenAlexSource(
                    api_key=settings.openalex_api_key,
                    user_agent=settings.wikipedia_user_agent,
                ))
        with Session(engine) as session:
            subjects = list_dinosaur_knowledge_subjects(session, names=dinos)
            summary = acquire_dinosaur_knowledge(
                session,
                subjects=subjects,
                wikipedia=wikipedia,
                openalex=openalex,
                sources=requested,
                max_items=max_items,
                overwrite=overwrite,
                dry_run=dry_run,
                openalex_limit=settings.openalex_max_works,
            )
    print(summary.model_dump_json(indent=2))
    return summary.exit_code
