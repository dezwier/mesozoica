"""Explicitly opt-in Azure smoke tests; normal CI never reaches cloud services."""

from __future__ import annotations

import os
import uuid

import pytest

from mesozoica_ai import (
    AiConfig as KnowledgeConfig,
    embed_query,
    ensure_index,
    retrieve_chunks,
    sync_documents,
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
    config = KnowledgeConfig()
    ensure_index(config=config)
    namespace = f"integration-{uuid.uuid4().hex}"
    document = {
        "id": f"{namespace}:document",
        "text": "A quokka is a small marsupial native to Western Australia.",
        "metadata": {
            "source": "integration", "source_id": namespace, "title": "Quokka",
            "section": "Introduction", "namespace": namespace, "subject_id": "quokka",
        },
    }
    scope = {"namespace": namespace, "subject_id": "quokka", "source": "integration"}
    try:
        sync_documents([document], scope=scope, config=config)
        query = "Where are quokkas native?"
        chunks = retrieve_chunks(
            query,
            query_embedding=embed_query(query, config=config),
            filters={"namespace": namespace},
            config=config,
        )
        assert chunks and chunks[0].document_id == document["id"]
    finally:
        sync_documents([], scope=scope, config=config)
