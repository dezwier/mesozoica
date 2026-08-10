"""Build or incrementally synchronize the Azure dinosaur knowledge index."""

from __future__ import annotations

from sqlmodel import Session

from app.core.database import engine
from app.features.ingestion.application.knowledge import index_dinosaur_knowledge
from mesozoica_ai.knowledge import (
    KnowledgeBaseSettings,
    create_knowledge_base,
    create_knowledge_index,
)


def run_index_job(
    *,
    dry_run: bool = False,
    overwrite: bool = False,
    recreate_index: bool = False,
    max_items: int | None = None,
    dinos: list[str] | None = None,
    sources: list[str] | None = None,
) -> int:
    settings = KnowledgeBaseSettings()
    with Session(engine) as session:
        summary = index_dinosaur_knowledge(
            session,
            knowledge=create_knowledge_base(settings),
            index=create_knowledge_index(settings),
            dinosaur_names=dinos,
            sources=sources,
            max_items=max_items,
            overwrite=overwrite,
            dry_run=dry_run,
            recreate_index=recreate_index,
        )
    print(summary.model_dump_json(indent=2))
    return summary.exit_code
