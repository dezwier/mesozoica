"""Print durable acquisition and indexing status for dinosaur knowledge."""

from __future__ import annotations

from sqlmodel import Session

from app.core.database import engine
from app.features.ingestion.application.knowledge import format_knowledge_status
from mesozoica_ai.knowledge import KnowledgeBaseSettings, create_knowledge_base


def run_status_job(*, dinos: list[str] | None = None) -> int:
    fingerprint = create_knowledge_base(
        KnowledgeBaseSettings(), write_enabled=False
    ).pipeline_fingerprint
    with Session(engine) as session:
        print(format_knowledge_status(
            session, dinosaur_names=dinos, current_pipeline_fingerprint=fingerprint
        ))
    return 0
