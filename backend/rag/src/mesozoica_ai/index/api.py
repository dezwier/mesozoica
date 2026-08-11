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
    PrepareEmbeddingsResult,
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


def prepare_embeddings(
    documents: Sequence[ModelInput],
    *,
    config: KnowledgeConfig,
    existing: Sequence[EmbeddedChunk | Mapping[str, Any]] | None = None,
) -> PrepareEmbeddingsResult:
    """Chunk documents and embed only chunks whose vector content changed.

    ``existing`` is typically prior ``embedded_chunks`` from SQL. Matching
    ``id`` + ``embedding_hash`` + ``pipeline_fingerprint`` reuses vectors.
    """
    normalized = _normalize_documents(documents)
    chunker = build_chunker(config)
    chunks = chunker.split(normalized)
    prior = {
        chunk.id: chunk
        for chunk in (
            _validate_model(EmbeddedChunk, item) for item in (existing or ())
        )
    }
    to_embed: list[KnowledgeChunk] = []
    reused: list[EmbeddedChunk] = []
    for chunk in chunks:
        previous = prior.get(chunk.id)
        if (
            previous is not None
            and previous.embedding_hash == chunk.embedding_hash
            and previous.pipeline_fingerprint == chunk.pipeline_fingerprint
            and previous.embedding
        ):
            reused.append(
                EmbeddedChunk(
                    **chunk.model_dump(exclude={"embedding"}),
                    embedding=previous.embedding,
                )
            )
        else:
            to_embed.append(chunk)
    freshly_embedded = build_embedder(config).embed(to_embed) if to_embed else []
    by_id = {chunk.id: chunk for chunk in (*reused, *freshly_embedded)}
    ordered = [by_id[chunk.id] for chunk in chunks]
    if to_embed:
        logger.info(
            "prepare_embeddings: embed %s/%s chunks (reused %s)",
            len(to_embed),
            len(chunks),
            len(reused),
        )
    else:
        logger.info(
            "prepare_embeddings: reuse all %s chunks",
            len(chunks),
        )
    return PrepareEmbeddingsResult(
        document_count=len(normalized),
        chunk_count=len(chunks),
        embedded_count=len(freshly_embedded),
        reused_count=len(reused),
        chunks=ordered,
        pipeline_fingerprint=chunker.pipeline_fingerprint,
    )


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


def sync_embedded_chunks(
    embedded_chunks: Sequence[EmbeddedChunk | Mapping[str, Any]],
    *,
    scope: dict[str, Any],
    config: KnowledgeConfig,
) -> SyncResult:
    """Upsert prepared embeddings into Azure without calling the embedding API."""
    if not scope:
        raise ValueError("sync scope must contain at least one exact-match filter")
    label = _scope_label(scope)
    normalized = [_validate_model(EmbeddedChunk, chunk) for chunk in embedded_chunks]
    _validate_embedded_scope(normalized, scope)
    store = build_store(config, write_enabled=True)
    current = {chunk.id: chunk for chunk in normalized}
    existing = store.get_chunk_states_by_ids(list(current))
    to_upsert = [
        chunk
        for chunk in normalized
        if chunk.id not in existing
        or existing[chunk.id].embedding_hash != chunk.embedding_hash
        or existing[chunk.id].pipeline_fingerprint != chunk.pipeline_fingerprint
    ]
    upsert_ids = {chunk.id for chunk in to_upsert}
    metadata_only = [
        chunk
        for chunk in normalized
        if chunk.id in existing
        and chunk.id not in upsert_ids
        and existing[chunk.id].document_hash != chunk.document_hash
    ]
    if to_upsert:
        logger.info(
            "%s: upsert %s/%s embedded chunks (Azure already has %s)",
            label,
            len(to_upsert),
            len(normalized),
            len(existing),
        )
        store.upsert(to_upsert)
    else:
        logger.info(
            "%s: skip upsert (%s chunks already in Azure)",
            label,
            len(normalized),
        )
    if metadata_only:
        store.merge_metadata(metadata_only)
    stale_ids = sorted(set(store.list_ids(scope)) - set(current))
    if stale_ids:
        store.delete(stale_ids)

    missing_after = _wait_for_keys(store, list(current), label=label)
    if missing_after:
        raise RuntimeError(
            f"{label}: after sync Azure key lookup still missing "
            f"{len(missing_after)}/{len(current)} chunks "
            f"(sample: {', '.join(missing_after[:3])})"
        )

    fingerprint = (
        normalized[0].pipeline_fingerprint
        if normalized
        else pipeline_fingerprint(config=config)
    )
    return SyncResult(
        document_count=len({chunk.document_id for chunk in normalized}),
        chunk_count=len(normalized),
        embedded_count=len(to_upsert),
        metadata_updated_count=len(metadata_only),
        skipped_count=len(normalized) - len(to_upsert) - len(metadata_only),
        deleted_count=len(stale_ids),
        chunk_ids=sorted(current),
        pipeline_fingerprint=fingerprint,
    )


def sync_documents(
    documents: Sequence[ModelInput],
    *,
    scope: dict[str, Any],
    config: KnowledgeConfig,
) -> SyncResult:
    """Chunk, embed, and synchronize one scope (ad-hoc path without SQL cache)."""
    prepared = prepare_embeddings(documents, config=config)
    result = sync_embedded_chunks(prepared.chunks, scope=scope, config=config)
    return result.model_copy(update={"embedded_count": prepared.embedded_count})


def _scope_label(scope: dict[str, Any]) -> str:
    subject = scope.get("subject_id") or scope.get("namespace") or "?"
    source = scope.get("source") or "?"
    return f"{subject}/{source}"


def _wait_for_keys(
    store: Any,
    ids: list[str],
    *,
    label: str,
    attempts: int = 5,
    delay_seconds: float = 1.0,
) -> list[str]:
    """Retry key lookup briefly so post-upsert eventual consistency can catch up."""
    missing = sorted(ids)
    for attempt in range(1, attempts + 1):
        found = store.existing_ids(ids)
        missing = sorted(set(ids) - found)
        if not missing:
            return []
        if attempt < attempts:
            logger.info(
                "%s: waiting for Azure keys (%s missing, attempt %s/%s)",
                label,
                len(missing),
                attempt,
                attempts,
            )
            time.sleep(delay_seconds * attempt)
    return missing


def azure_knowledge_overview(
    *,
    config: KnowledgeConfig,
    session: Any | None = None,
    model: type[Any] | None = None,
):
    """Summarize dinosaurs / wiki / papers / chunks currently in Azure Search.

    When ``session``/``model`` are provided, expected chunk IDs are derived from
    SQL documents and probed with key lookup (not search=*), which is reliable
    on indexes where wildcard scope scans under-count.
    """
    from mesozoica_ai.common.batch import DEFAULT_SUBJECT_KIND, snapshot_scope
    from mesozoica_ai.common.inventory import KnowledgeOverview
    from sqlmodel import select

    store = build_store(config, write_enabled=False)
    if session is None or model is None:
        from mesozoica_ai.common.inventory import azure_knowledge_overview_from_rows

        return azure_knowledge_overview_from_rows(store.inventory_rows())

    statement = select(model).where(
        model.subject_kind == DEFAULT_SUBJECT_KIND,
        model.acquisition_status == "succeeded",
    )
    sql_rows = list(session.exec(statement).all())

    subjects: set[str] = set()
    wiki_subjects: set[str] = set()
    openalex_subjects: set[str] = set()
    papers: set[tuple[str, str]] = set()
    wiki_chunks = 0
    openalex_chunks = 0

    for row in sql_rows:
        scope = snapshot_scope(row)
        subject = str(scope.get("subject_id") or "")
        source = str(row.source or "").casefold()
        if getattr(row, "embedded_chunks", None):
            chunk_ids = [
                str(chunk.get("id") or "")
                for chunk in row.embedded_chunks
                if chunk.get("id")
            ]
            chunks_by_id = {
                str(chunk.get("id")): chunk
                for chunk in row.embedded_chunks
                if chunk.get("id")
            }
        else:
            chunks = chunk_documents(list(row.documents or []), config=config)
            chunk_ids = [chunk.id for chunk in chunks]
            chunks_by_id = {
                chunk.id: chunk.model_dump(mode="json") for chunk in chunks
            }
        found_ids = store.existing_ids(chunk_ids)
        if not found_ids:
            continue
        subjects.add(subject)
        if source == "wikipedia":
            wiki_subjects.add(subject)
            wiki_chunks += len(found_ids)
        elif source == "openalex":
            openalex_subjects.add(subject)
            openalex_chunks += len(found_ids)
            for chunk_id in found_ids:
                chunk = chunks_by_id.get(chunk_id) or {}
                metadata = chunk.get("metadata") or {}
                source_id = str(metadata.get("source_id") or "").strip()
                if subject and source_id:
                    papers.add((subject, source_id))

    return KnowledgeOverview(
        dinosaurs=len(subjects),
        wikipedia_dinos=len(wiki_subjects),
        wikipedia_units=wiki_chunks,
        openalex_dinos=len(openalex_subjects),
        openalex_papers=len(papers),
        openalex_units=openalex_chunks,
        unit_label="chunks",
    )


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
    mode: RetrievalMode | None = None,
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
    mode: RetrievalMode | None = None,
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
    mode: RetrievalMode | None = None,
    candidate_k: int | None = None,
    fetch_k: int | None = None,
    top_k: int | None = None,
    evidence_policy: EvidencePolicy | None = None,
    include_diagnostics: bool = False,
    config: KnowledgeConfig,
) -> list[RetrievedChunk] | RetrievalResult:
    """Retrieve guarded chunks, optionally including ranking diagnostics."""
    from azure.core.exceptions import HttpResponseError

    started = time.perf_counter()
    active_mode = mode or RetrievalMode(config.retrieval_mode)
    vector_modes = {
        RetrievalMode.VECTOR,
        RetrievalMode.HYBRID,
        RetrievalMode.SEMANTIC_HYBRID,
    }
    if active_mode in vector_modes and query_embedding is None:
        raise ValueError(f"{active_mode.value} retrieval requires an explicit query_embedding")
    request = RetrievalRequest(
        query=query,
        filters=filters or {},
        mode=active_mode,
        candidate_k=config.candidate_k if candidate_k is None else candidate_k,
        fetch_k=config.fetch_k if fetch_k is None else fetch_k,
        top_k=config.top_k if top_k is None else top_k,
        evidence_policy=evidence_policy or EvidencePolicy(),
    )
    store = build_store(config, write_enabled=False)
    try:
        raw = store.search(
            request=request,
            query_vector=query_embedding if active_mode in vector_modes else None,
        )
    except HttpResponseError as exc:
        if (
            active_mode is RetrievalMode.SEMANTIC_HYBRID
            and _semantic_ranker_unavailable(exc)
        ):
            logger.warning(
                "semantic ranker unavailable on this Azure Search service; "
                "falling back to hybrid (set RAG_RETRIEVAL_MODE=hybrid to skip this)"
            )
            active_mode = RetrievalMode.HYBRID
            request = request.model_copy(update={"mode": active_mode})
            raw = store.search(
                request=request,
                query_vector=query_embedding,
            )
        else:
            raise
    selected, rejected = _select_evidence(raw, request)
    result = RetrievalResult(
        chunks=selected,
        raw_result_count=len(raw),
        rejection_counts=rejected,
        mode=active_mode,
        duration_ms=(time.perf_counter() - started) * 1000,
        pipeline_fingerprint=pipeline_fingerprint(config=config),
    )
    logger.info("rag.retrieve", extra={"rag": {
        "mode": active_mode.value,
        "raw_count": len(raw),
        "selected_count": len(selected),
        "duration_ms": result.duration_ms,
        "pipeline_fingerprint": result.pipeline_fingerprint,
    }})
    return result if include_diagnostics else result.chunks


def _semantic_ranker_unavailable(exc: BaseException) -> bool:
    text = str(exc)
    return (
        "SemanticQueriesNotAvailable" in text
        or "Semantic search is not enabled" in text
        or "FeatureNotSupportedInService" in text
    )


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
        if not raw:
            raise InsufficientEvidenceError(
                "Retrieval returned 0 chunks from Azure Search for this query/filter. "
                "Acquire, embed, and ingest the subject first "
                "(rag/scripts/01_acquire_dinosaur_knowledge.py, "
                "02_embed_dinosaur_knowledge.py, then "
                "03_ingest_dinosaur_knowledge.py)."
            )
        raise InsufficientEvidenceError(
            f"Retrieval selected {len(selected)} usable chunks from {len(raw)} raw "
            f"hit(s); policy requires at least {policy.minimum_chunks}"
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


def _validate_embedded_scope(
    chunks: list[EmbeddedChunk], scope: dict[str, Any]
) -> None:
    for chunk in chunks:
        metadata = chunk.metadata.model_dump(mode="json", exclude_none=True)
        for field, expected in scope.items():
            actual = chunk.document_id if field == "document_id" else metadata.get(field)
            if actual != expected:
                raise ValueError(
                    f"Chunk {chunk.id!r} does not match sync scope "
                    f"{field}={expected!r}"
                )
