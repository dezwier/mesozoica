"""Explicitly opt-in Azure smoke tests; normal CI never reaches cloud services."""

from __future__ import annotations

import os
import uuid

import pytest

from mesozoica_ai.knowledge import (
    KnowledgeBaseSettings,
    KnowledgeDocument,
    RetrievalRequest,
    create_knowledge_base,
    create_knowledge_index,
)


pytestmark = [
    pytest.mark.live,
    pytest.mark.skipif(
        os.getenv("RAG_LIVE_ALLOW_WRITES") != "1",
        reason="set RAG_LIVE_ALLOW_WRITES=1 only against a disposable Azure index",
    ),
]


def test_live_index_sync_and_semantic_hybrid_retrieval() -> None:
    """Validate the deployed schema, embeddings, writes, and default retrieval end to end."""
    settings = KnowledgeBaseSettings()
    create_knowledge_index(settings).ensure()
    knowledge = create_knowledge_base(settings)
    namespace = f"integration-{uuid.uuid4().hex}"
    document = KnowledgeDocument(
        id=f"{namespace}:document",
        text="A quokka is a small marsupial native to Western Australia.",
        metadata={
            "source": "integration", "source_id": namespace, "title": "Quokka",
            "section": "Introduction", "namespace": namespace, "subject_id": "quokka",
        },
    )
    scope = {"namespace": namespace, "subject_id": "quokka", "source": "integration"}
    try:
        knowledge.sync([document], scope=scope)
        result = knowledge.retrieve(RetrievalRequest(
            query="Where are quokkas native?", filters={"namespace": namespace},
        ))
        assert result.chunks and result.chunks[0].document_id == document.id
    finally:
        knowledge.clear(scope)
