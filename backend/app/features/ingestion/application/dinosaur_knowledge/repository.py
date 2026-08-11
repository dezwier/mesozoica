"""SQL knowledge repository wiring for dinosaur knowledge tables."""

from __future__ import annotations

from typing import Any

from mesozoica_ai.common import SqlModelKnowledgeRepository
from app.features.ingestion.models import (
    DinosaurKnowledgeChunk,
    DinosaurKnowledgeDoc,
    DinosaurKnowledgeSource,
)


def dinosaur_knowledge_repo(session: Any) -> SqlModelKnowledgeRepository:
    """Build the normalized source/doc/chunk repository for one session."""
    return SqlModelKnowledgeRepository(
        session,
        source_model=DinosaurKnowledgeSource,
        doc_model=DinosaurKnowledgeDoc,
        chunk_model=DinosaurKnowledgeChunk,
    )
