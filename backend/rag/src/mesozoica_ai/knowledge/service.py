"""High-level document synchronization and retrieval service."""

from __future__ import annotations

import hashlib
import logging
import time
from collections import Counter
from typing import Any

from .errors import InsufficientEvidenceError
from .models import (
    IngestResult,
    KnowledgeDocument,
    RejectionCounts,
    RetrievalMode,
    RetrievalRequest,
    RetrievalResult,
    RetrievedChunk,
    SyncResult,
)

from .chunking import RecursiveChunker
from .embeddings import Embedder
from .store import KnowledgeStore

logger = logging.getLogger(__name__)


class KnowledgeBase:
    """Chunk, synchronize, and retrieve generic knowledge documents."""

    def __init__(self, *, chunker: RecursiveChunker, embedder: Embedder, store: KnowledgeStore):
        self.chunker = chunker
        self.embedder = embedder
        self.store = store

    @property
    def pipeline_fingerprint(self) -> str:
        """Return the active compatibility fingerprint used by checkpoints."""
        return self.chunker.pipeline_fingerprint

    def ingest(self, documents: list[KnowledgeDocument]) -> IngestResult:
        """Unconditionally embed and upsert documents."""
        chunks = self.chunker.split(documents)
        self.store.upsert(self.embedder.embed(chunks))
        return IngestResult(
            document_count=len(documents),
            chunk_count=len(chunks),
            chunk_ids=[chunk.id for chunk in chunks],
            pipeline_fingerprint=self.pipeline_fingerprint,
        )

    def sync(self, documents: list[KnowledgeDocument], *, scope: dict[str, Any]) -> SyncResult:
        """Safely synchronize one exact scope, deleting stale chunks only after writes."""
        if not scope:
            raise ValueError("sync scope must contain at least one exact-match filter")
        _validate_document_scope(documents, scope)
        chunks = self.chunker.split(documents)
        current = {chunk.id: chunk for chunk in chunks}
        existing = self.store.get_chunk_states(scope)
        embed = [
            chunk
            for chunk in chunks
            if chunk.id not in existing
            or existing[chunk.id].embedding_hash != chunk.embedding_hash
            or existing[chunk.id].pipeline_fingerprint != chunk.pipeline_fingerprint
        ]
        embed_ids = {chunk.id for chunk in embed}
        metadata_only = [
            chunk
            for chunk in chunks
            if chunk.id in existing
            and chunk.id not in embed_ids
            and existing[chunk.id].document_hash != chunk.document_hash
        ]
        # Writes intentionally precede deletion: a partial write can never erase the last
        # usable version of a source scope.
        self.store.upsert(self.embedder.embed(embed))
        self.store.merge_metadata(metadata_only)
        stale_ids = sorted(set(existing) - set(current))
        self.store.delete(stale_ids)
        result = SyncResult(
            document_count=len(documents),
            chunk_count=len(chunks),
            embedded_count=len(embed),
            metadata_updated_count=len(metadata_only),
            skipped_count=len(chunks) - len(embed) - len(metadata_only),
            deleted_count=len(stale_ids),
            chunk_ids=sorted(current),
            pipeline_fingerprint=self.pipeline_fingerprint,
        )
        logger.info("rag.index.sync", extra={"rag": result.model_dump(exclude={"chunk_ids"})})
        return result

    def retrieve(self, request: RetrievalRequest) -> RetrievalResult:
        """Retrieve ranked candidates and enforce deterministic evidence guardrails."""
        started = time.perf_counter()
        query_vector = None
        if request.mode in {
            RetrievalMode.VECTOR,
            RetrievalMode.HYBRID,
            RetrievalMode.SEMANTIC_HYBRID,
        }:
            query_vector = self.embedder.embed_query(request.query)
        raw = self.store.search(request=request, query_vector=query_vector)
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
        result = RetrievalResult(
            chunks=selected,
            raw_result_count=len(raw),
            rejection_counts=rejected,
            mode=request.mode,
            duration_ms=(time.perf_counter() - started) * 1000,
            pipeline_fingerprint=self.pipeline_fingerprint,
        )
        logger.info(
            "rag.retrieve",
            extra={
                "rag": {
                    "mode": request.mode.value,
                    "raw_count": len(raw),
                    "selected_count": len(selected),
                    "duration_ms": result.duration_ms,
                    "pipeline_fingerprint": self.pipeline_fingerprint,
                }
            },
        )
        return result

    def search(self, query: str, **kwargs: Any) -> RetrievalResult:
        """Convenience wrapper around :meth:`retrieve`."""
        return self.retrieve(RetrievalRequest(query=query, **kwargs))

    def clear(self, filters: dict[str, Any] | None = None) -> int:
        """Delete an explicit exact-match scope."""
        if not filters:
            raise ValueError("clear requires at least one exact-match filter")
        ids = self.store.list_ids(filters)
        self.store.delete(ids)
        return len(ids)


def _validate_document_scope(documents: list[KnowledgeDocument], scope: dict[str, Any]) -> None:
    for document in documents:
        metadata = document.metadata.model_dump(mode="json", exclude_none=True)
        for field, expected in scope.items():
            actual = document.id if field == "document_id" else metadata.get(field)
            if actual != expected:
                raise ValueError(
                    f"Document {document.id!r} does not match sync scope {field}={expected!r}"
                )
