"""
Build dinosaur knowledge: acquire Wikipedia/OpenAlex snapshots, then index.

Run manually:
  python -m app.crons.runner --job dinosaur_knowledge
  python -m app.crons.runner --job dinosaur_knowledge --dinos Tyrannosaurus
  python -m app.crons.runner --job dinosaur_knowledge --sources wikipedia
"""

from __future__ import annotations

from sqlmodel import Session

from app.core.config import settings
from app.core.database import engine
from app.features.ingestion.models.dinosaur_knowledge import DinosaurKnowledge
from app.features.specimens.public import list_dinosaur_knowledge_subjects
from mesozoica_ai.index import index_knowledge
from mesozoica_ai.sources import acquire_knowledge


def run_knowledge_job(
    *,
    dry_run: bool = False,
    overwrite: bool = False,
    recreate_index: bool = False,
    dinos: list[str] | None = None,
    sources: list[str] | None = None,
    max_items: int | None = None,
) -> int:
    """Fetch source docs for all dinosaurs, store them, then index into Azure Search."""
    with Session(engine) as session:
        subjects = list_dinosaur_knowledge_subjects(session, names=dinos)

        acquire = acquire_knowledge(
            session,
            DinosaurKnowledge,
            subjects=subjects,
            user_agent=settings.wikipedia_user_agent,
            openalex_api_key=settings.openalex_api_key or "",
            openalex_limit=settings.openalex_max_works,
            sources=sources,
            max_items=max_items,
            overwrite=overwrite,
            dry_run=dry_run,
        )
        index = index_knowledge(
            session=session,
            model=DinosaurKnowledge,
            names=dinos,
            sources=sources,
            max_items=max_items,
            overwrite=overwrite,
            dry_run=dry_run,
            recreate_index=recreate_index,
        )

    print({"acquire": acquire.model_dump(), "index": index.model_dump()})
    return 1 if acquire.failed or index.failed else 0
