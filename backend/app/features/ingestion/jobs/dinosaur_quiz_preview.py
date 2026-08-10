"""Generate one non-persisted structured RAG quiz for manual inspection."""

from __future__ import annotations

from sqlmodel import Session

from app.core.database import engine
from app.features.ingestion.application.knowledge import generate_quiz_preview
from app.features.specimens.public import list_dinosaur_knowledge_subjects
from mesozoica_ai.knowledge import KnowledgeBaseSettings, create_knowledge_base
from mesozoica_ai.rag import RagSettings, create_rag


def run_preview_job(*, dinos: list[str] | None = None) -> int:
    if not dinos or len(dinos) != 1:
        raise ValueError("dinosaur_quiz_preview requires exactly one --dinos value")
    with Session(engine) as session:
        subjects = list_dinosaur_knowledge_subjects(session, names=dinos)
    if len(subjects) != 1:
        raise ValueError(f"Dinosaur not found: {dinos[0]}")
    subject = subjects[0]
    quiz = generate_quiz_preview(
        knowledge=create_knowledge_base(KnowledgeBaseSettings(), write_enabled=False),
        rag=create_rag(RagSettings()),
        dinosaur_id=subject.id,
        dinosaur_name=subject.name,
    )
    print(quiz.model_dump_json(indent=2))
    return 0
