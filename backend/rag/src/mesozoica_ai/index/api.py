"""Flat public operations for document processing, indexing, and retrieval."""

from __future__ import annotations

import hashlib
import logging
import time
from collections import Counter
from collections.abc import Mapping, Sequence
from typing import Any, Literal, TypeVar, overload

from pydantic import BaseModel

from mesozoica_ai.common.config import AiConfig as KnowledgeConfig
from mesozoica_ai.common.errors import InsufficientEvidenceError
from mesozoica_ai.common.models import (
    EmbeddedChunk,
    EvidencePolicy,
    IndexResult,
    KnowledgeChunk,
    KnowledgeDocument,
    RejectionCounts,
    RetrievalMode,
    RetrievalRequest,
    RetrievalResult,
    RetrievedChunk,
    SyncResult,
)
from .runtime import build_chunker, build_embedder, build_index, build_store

logger = logging.getLogger(__name__)
ModelInput = BaseModel | Mapping[str, Any]
ModelT = TypeVar("ModelT", bound=BaseModel)


def chunk_documents(
    documents: Sequence[ModelInput], *, config: KnowledgeConfig
) -> list[KnowledgeChunk]:
    """Normalize and split source documents without crossing document boundaries."""
    return build_chunker(config).split(_normalize_documents(documents))


def embed_chunks(
    chunks: Sequence[KnowledgeChunk | Mapping[str, Any]], *, config: KnowledgeConfig
) -> list[EmbeddedChunk]:
    """Embed prepared chunks using their contextual embedding text."""
    normalized = [_validate_model(KnowledgeChunk, chunk) for chunk in chunks]
    return build_embedder(config).embed(normalized)


def ensure_index(*, config: KnowledgeConfig) -> None:
    """Create a missing Azure index or validate the existing compatible schema."""
    build_index(config).ensure()


def recreate_index(*, config: KnowledgeConfig) -> None:
    """Explicitly delete and recreate the configured Azure index."""
    build_index(config).recreate()


def index_chunks(
    chunks: Sequence[EmbeddedChunk | Mapping[str, Any]], *, config: KnowledgeConfig
) -> IndexResult:
    """Unconditionally upsert embedded chunks without deleting stale documents."""
    normalized = [_validate_model(EmbeddedChunk, chunk) for chunk in chunks]
    build_store(config, write_enabled=True).upsert(normalized)
    return IndexResult(
        indexed_count=len(normalized),
        chunk_ids=[chunk.id for chunk in normalized],
    )


def sync_documents(
    documents: Sequence[ModelInput],
    *,
    scope: dict[str, Any],
    config: KnowledgeConfig,
) -> SyncResult:
    """Safely synchronize one scope while embedding only vector-changed chunks."""
    if not scope:
        raise ValueError("sync scope must contain at least one exact-match filter")
    normalized = _normalize_documents(documents)
    _validate_document_scope(normalized, scope)
    chunker = build_chunker(config)
    chunks = chunker.split(normalized)
    store = build_store(config, write_enabled=True)
    current = {chunk.id: chunk for chunk in chunks}
    existing = store.get_chunk_states(scope)
    to_embed = [
        chunk
        for chunk in chunks
        if chunk.id not in existing
        or existing[chunk.id].embedding_hash != chunk.embedding_hash
        or existing[chunk.id].pipeline_fingerprint != chunk.pipeline_fingerprint
    ]
    embed_ids = {chunk.id for chunk in to_embed}
    metadata_only = [
        chunk
        for chunk in chunks
        if chunk.id in existing
        and chunk.id not in embed_ids
        and existing[chunk.id].document_hash != chunk.document_hash
    ]
    # Writes precede deletion so partial failures cannot erase the last usable scope.
    store.upsert(build_embedder(config).embed(to_embed))
    store.merge_metadata(metadata_only)
    stale_ids = sorted(set(existing) - set(current))
    store.delete(stale_ids)
    result = SyncResult(
        document_count=len(normalized),
        chunk_count=len(chunks),
        embedded_count=len(to_embed),
        metadata_updated_count=len(metadata_only),
        skipped_count=len(chunks) - len(to_embed) - len(metadata_only),
        deleted_count=len(stale_ids),
        chunk_ids=sorted(current),
        pipeline_fingerprint=chunker.pipeline_fingerprint,
    )
    logger.info("rag.index.sync", extra={"rag": result.model_dump(exclude={"chunk_ids"})})
    return result


def pipeline_fingerprint(*, config: KnowledgeConfig) -> str:
    """Return the compatibility fingerprint represented by the knowledge config."""
    return build_chunker(config).pipeline_fingerprint


def embed_query(query: str, *, config: KnowledgeConfig) -> list[float]:
    """Embed one nonblank retrieval query."""
    if not query.strip():
        raise ValueError("query must not be blank")
    return build_embedder(config).embed_query(query)


@overload
def retrieve_chunks(
    query: str,
    *,
    query_embedding: list[float] | None,
    filters: dict[str, Any] | None = None,
    mode: RetrievalMode = RetrievalMode.SEMANTIC_HYBRID,
    candidate_k: int | None = None,
    fetch_k: int | None = None,
    top_k: int | None = None,
    evidence_policy: EvidencePolicy | None = None,
    include_diagnostics: Literal[False] = False,
    config: KnowledgeConfig,
) -> list[RetrievedChunk]: ...


@overload
def retrieve_chunks(
    query: str,
    *,
    query_embedding: list[float] | None,
    filters: dict[str, Any] | None = None,
    mode: RetrievalMode = RetrievalMode.SEMANTIC_HYBRID,
    candidate_k: int | None = None,
    fetch_k: int | None = None,
    top_k: int | None = None,
    evidence_policy: EvidencePolicy | None = None,
    include_diagnostics: Literal[True],
    config: KnowledgeConfig,
) -> RetrievalResult: ...


def retrieve_chunks(
    query: str,
    *,
    query_embedding: list[float] | None,
    filters: dict[str, Any] | None = None,
    mode: RetrievalMode = RetrievalMode.SEMANTIC_HYBRID,
    candidate_k: int | None = None,
    fetch_k: int | None = None,
    top_k: int | None = None,
    evidence_policy: EvidencePolicy | None = None,
    include_diagnostics: bool = False,
    config: KnowledgeConfig,
) -> list[RetrievedChunk] | RetrievalResult:
    """Retrieve guarded chunks, optionally including ranking diagnostics."""
    started = time.perf_counter()
    vector_modes = {
        RetrievalMode.VECTOR,
        RetrievalMode.HYBRID,
        RetrievalMode.SEMANTIC_HYBRID,
    }
    if mode in vector_modes and query_embedding is None:
        raise ValueError(f"{mode.value} retrieval requires an explicit query_embedding")
    request = RetrievalRequest(
        query=query,
        filters=filters or {},
        mode=mode,
        candidate_k=config.candidate_k if candidate_k is None else candidate_k,
        fetch_k=config.fetch_k if fetch_k is None else fetch_k,
        top_k=config.top_k if top_k is None else top_k,
        evidence_policy=evidence_policy or EvidencePolicy(),
    )
    raw = build_store(config, write_enabled=False).search(
        request=request,
        query_vector=query_embedding if mode in vector_modes else None,
    )
    selected, rejected = _select_evidence(raw, request)
    result = RetrievalResult(
        chunks=selected,
        raw_result_count=len(raw),
        rejection_counts=rejected,
        mode=mode,
        duration_ms=(time.perf_counter() - started) * 1000,
        pipeline_fingerprint=pipeline_fingerprint(config=config),
    )
    logger.info("rag.retrieve", extra={"rag": {
        "mode": mode.value,
        "raw_count": len(raw),
        "selected_count": len(selected),
        "duration_ms": result.duration_ms,
        "pipeline_fingerprint": result.pipeline_fingerprint,
    }})
    return result if include_diagnostics else result.chunks


def _select_evidence(
    raw: list[RetrievedChunk], request: RetrievalRequest
) -> tuple[list[RetrievedChunk], RejectionCounts]:
    selected: list[RetrievedChunk] = []
    content_hashes: set[str] = set()
    per_document: Counter[str] = Counter()
    rejected = RejectionCounts()
    policy = request.evidence_policy
    for chunk in raw:
        if (
            policy.minimum_reranker_score is not None
            and (chunk.reranker_score is None or chunk.reranker_score < policy.minimum_reranker_score)
        ):
            rejected.below_threshold += 1
            continue
        exact_hash = hashlib.sha256(chunk.text.strip().encode("utf-8")).hexdigest()
        if policy.deduplicate_exact_content and exact_hash in content_hashes:
            rejected.duplicate_content += 1
            continue
        if per_document[chunk.document_id] >= policy.max_chunks_per_document:
            rejected.per_document_cap += 1
            continue
        selected.append(chunk)
        content_hashes.add(exact_hash)
        per_document[chunk.document_id] += 1
        if len(selected) >= request.top_k:
            break
    if len(selected) < policy.minimum_chunks:
        raise InsufficientEvidenceError(
            f"Retrieval selected {len(selected)} usable chunks; policy requires "
            f"at least {policy.minimum_chunks}"
        )
    return selected, rejected


def _normalize_documents(documents: Sequence[ModelInput]) -> list[KnowledgeDocument]:
    return [_validate_model(KnowledgeDocument, document) for document in documents]


def _validate_model(
    model: type[ModelT], value: BaseModel | Mapping[str, Any]
) -> ModelT:
    data = value.model_dump(mode="json") if isinstance(value, BaseModel) else dict(value)
    return model.model_validate(data)


def _validate_document_scope(
    documents: list[KnowledgeDocument], scope: dict[str, Any]
) -> None:
    for document in documents:
        metadata = document.metadata.model_dump(mode="json", exclude_none=True)
        for field, expected in scope.items():
            actual = document.id if field == "document_id" else metadata.get(field)
            if actual != expected:
                raise ValueError(
                    f"Document {document.id!r} does not match sync scope "
                    f"{field}={expected!r}"
                )
