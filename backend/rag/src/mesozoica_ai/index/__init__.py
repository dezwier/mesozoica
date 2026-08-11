"""Chunk, sync, and retrieve Azure AI Search knowledge."""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from typing import Any, Literal, overload

from . import api as _api
from mesozoica_ai.common.config import AiConfig
from mesozoica_ai.common.models import (
    EmbeddedChunk,
    EvidencePolicy,
    IndexResult,
    KnowledgeChunk,
    PrepareEmbeddingsResult,
    RetrievalMode,
    RetrievalResult,
    RetrievedChunk,
    SyncResult,
)

# Private helpers kept available for tests.
chunk_documents = _api.chunk_documents
embed_chunks = _api.embed_chunks
index_chunks = _api.index_chunks
prepare_embeddings = _api.prepare_embeddings
sync_embedded_chunks = _api.sync_embedded_chunks


def ensure_index(*, config: AiConfig) -> None:
    """Create a missing Azure index or validate the existing compatible schema."""
    _api.ensure_index(config=config)


def recreate_index(*, config: AiConfig) -> None:
    """Explicitly delete and recreate the configured Azure index."""
    _api.recreate_index(config=config)


def sync_documents(
    documents: Sequence[Any],
    *,
    scope: dict[str, Any],
    config: AiConfig,
) -> SyncResult:
    """Chunk, embed, and synchronize one scope (ad-hoc path without SQL cache)."""
    return _api.sync_documents(documents, scope=scope, config=config)


def pipeline_fingerprint(*, config: AiConfig) -> str:
    """Return the compatibility fingerprint represented by the active config."""
    return _api.pipeline_fingerprint(config=config)


def embed_query(query: str, *, config: AiConfig) -> list[float]:
    """Embed one nonblank retrieval query."""
    return _api.embed_query(query, config=config)


@overload
def retrieve_chunks(
    query: str,
    *,
    query_embedding: list[float] | None,
    filters: dict[str, Any] | None = None,
    mode: RetrievalMode | None = None,
    candidate_k: int | None = None,
    fetch_k: int | None = None,
    top_k: int | None = None,
    evidence_policy: EvidencePolicy | None = None,
    include_diagnostics: Literal[False] = False,
    config: AiConfig,
) -> list[RetrievedChunk]: ...


@overload
def retrieve_chunks(
    query: str,
    *,
    query_embedding: list[float] | None,
    filters: dict[str, Any] | None = None,
    mode: RetrievalMode | None = None,
    candidate_k: int | None = None,
    fetch_k: int | None = None,
    top_k: int | None = None,
    evidence_policy: EvidencePolicy | None = None,
    include_diagnostics: Literal[True],
    config: AiConfig,
) -> RetrievalResult: ...


def retrieve_chunks(
    query: str,
    *,
    query_embedding: list[float] | None,
    filters: dict[str, Any] | None = None,
    mode: RetrievalMode | None = None,
    candidate_k: int | None = None,
    fetch_k: int | None = None,
    top_k: int | None = None,
    evidence_policy: EvidencePolicy | None = None,
    include_diagnostics: bool = False,
    config: AiConfig,
) -> list[RetrievedChunk] | RetrievalResult:
    """Retrieve guarded chunks, optionally including ranking diagnostics."""
    return _api.retrieve_chunks(
        query,
        query_embedding=query_embedding,
        filters=filters,
        mode=mode,
        candidate_k=candidate_k,
        fetch_k=fetch_k,
        top_k=top_k,
        evidence_policy=evidence_policy,
        include_diagnostics=include_diagnostics,
        config=config,
    )


from .batch import (
    embed_knowledge,
    index_knowledge,
    ingest_knowledge,
    list_knowledge_rows,
    require_full_recreate_scope,
)

azure_knowledge_overview = _api.azure_knowledge_overview

__all__ = [
    "EmbeddedChunk",
    "EvidencePolicy",
    "IndexResult",
    "KnowledgeChunk",
    "PrepareEmbeddingsResult",
    "RetrievalMode",
    "RetrievalResult",
    "RetrievedChunk",
    "SyncResult",
    "azure_knowledge_overview",
    "chunk_documents",
    "embed_chunks",
    "embed_knowledge",
    "embed_query",
    "ensure_index",
    "index_chunks",
    "index_knowledge",
    "ingest_knowledge",
    "list_knowledge_rows",
    "pipeline_fingerprint",
    "prepare_embeddings",
    "recreate_index",
    "require_full_recreate_scope",
    "retrieve_chunks",
    "sync_documents",
    "sync_embedded_chunks",
]
