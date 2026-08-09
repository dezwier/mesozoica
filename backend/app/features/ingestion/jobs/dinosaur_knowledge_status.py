"""Print durable acquisition and indexing status for dinosaur knowledge."""

from __future__ import annotations

from sqlmodel import Session

from app.core.database import engine
from app.features.ingestion.application.knowledge import format_knowledge_status


def run_status_job(*, dinos: list[str] | None = None) -> int:
    with Session(engine) as session:
        print(format_knowledge_status(session, dinosaur_names=dinos))
    return 0
