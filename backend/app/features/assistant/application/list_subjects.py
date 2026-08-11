"""List dinosaurs that already have indexed knowledge (AI search)."""

from __future__ import annotations

from typing import Any

from sqlmodel import col, select

from app.features.assistant.schemas import KnowledgeSubject
from app.features.ingestion.models import (
    KNOWLEDGE_STATUS_SUCCEEDED,
    DinosaurKnowledgeSource,
)
from mesozoica_ai.common.batch import DEFAULT_SUBJECT_KIND


def list_indexed_subjects(session: Any) -> list[KnowledgeSubject]:
    """Distinct dinosaurs with at least one succeeded Azure index row."""
    rows = session.exec(
        select(
            DinosaurKnowledgeSource.subject_id,
            DinosaurKnowledgeSource.subject_name,
        )
        .where(
            DinosaurKnowledgeSource.subject_kind == DEFAULT_SUBJECT_KIND,
            DinosaurKnowledgeSource.index_status == KNOWLEDGE_STATUS_SUCCEEDED,
        )
        .distinct()
        .order_by(col(DinosaurKnowledgeSource.subject_name))
    ).all()
    subjects: list[KnowledgeSubject] = []
    seen: set[str] = set()
    for subject_id, subject_name in rows:
        sid = str(subject_id)
        if sid in seen:
            continue
        seen.add(sid)
        subjects.append(
            KnowledgeSubject(id=sid, name=str(subject_name).strip() or sid)
        )
    return subjects
