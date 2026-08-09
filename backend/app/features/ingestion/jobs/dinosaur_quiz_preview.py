"""Generate one non-persisted structured RAG quiz for manual inspection."""

from __future__ import annotations

from sqlmodel import Session

from app.core.database import engine
from app.features.ingestion.application.knowledge import generate_quiz_preview
from app.features.specimens.public import list_dinosaur_knowledge_subjects
from mesozoica_ai.knowledge import KnowledgeSettings, create_structured_rag


def run_preview_job(*, dinos: list[str] | None = None) -> int:
    if not dinos or len(dinos) != 1:
        raise ValueError("dinosaur_quiz_preview requires exactly one --dinos value")
    with Session(engine) as session:
        subjects = list_dinosaur_knowledge_subjects(session, names=dinos)
    if len(subjects) != 1:
        raise ValueError(f"Dinosaur not found: {dinos[0]}")
    subject = subjects[0]
    quiz = generate_quiz_preview(
        rag=create_structured_rag(KnowledgeSettings()),
        dinosaur_id=subject.id,
        dinosaur_name=subject.name,
    )
    print(quiz.model_dump_json(indent=2))
    return 0
