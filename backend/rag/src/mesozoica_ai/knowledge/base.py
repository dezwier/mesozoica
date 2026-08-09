from __future__ import annotations

from typing import Any

from .chunking import RecursiveChunker
from .embeddings import Embedder
from .models import (
    IngestResult,
    KnowledgeDocument,
    RetrievalRequest,
    RetrievedChunk,
    SearchMode,
    SyncResult,
)
from .store import KnowledgeStore


class KnowledgeBase:
    def __init__(self, *, chunker: RecursiveChunker, embedder: Embedder, store: KnowledgeStore):
        self.chunker = chunker
        self.embedder = embedder
        self.store = store

    def ingest(self, documents: list[KnowledgeDocument]) -> IngestResult:
        chunks = self.chunker.split(documents)
        self.store.upsert(self.embedder.embed(chunks))
        return IngestResult(
            document_count=len(documents),
            chunk_count=len(chunks),
            chunk_ids=[chunk.id for chunk in chunks],
        )

    def sync(self, documents: list[KnowledgeDocument], *, scope: dict[str, Any]) -> SyncResult:
        if not scope:
            raise ValueError("sync scope must contain at least one exact-match filter")
        _validate_document_scope(documents, scope)
        chunks = self.chunker.split(documents)
        current = {chunk.id: chunk for chunk in chunks}
        existing_hashes = self.store.get_content_hashes(scope)
        changed = [
            chunk for chunk in chunks if existing_hashes.get(chunk.id) != chunk.content_hash
        ]
        self.store.upsert(self.embedder.embed(changed))
        stale_ids = sorted(set(existing_hashes) - set(current))
        self.store.delete(stale_ids)
        return SyncResult(
            document_count=len(documents),
            chunk_count=len(chunks),
            embedded_count=len(changed),
            skipped_count=len(chunks) - len(changed),
            deleted_count=len(stale_ids),
            chunk_ids=sorted(current),
        )

    def retrieve(self, request: RetrievalRequest) -> list[RetrievedChunk]:
        query_vector = None
        if request.mode in {
            SearchMode.VECTOR,
            SearchMode.HYBRID,
            SearchMode.SEMANTIC_HYBRID,
        }:
            query_vector = self.embedder.embed_query(request.query)
        return self.store.search(request=request, query_vector=query_vector)

    def search(
        self,
        query: str,
        *,
        mode: SearchMode | str = SearchMode.SEMANTIC_HYBRID,
        filters: dict[str, Any] | None = None,
        top_k: int = 8,
        candidate_k: int = 50,
    ) -> list[RetrievedChunk]:
        return self.retrieve(
            RetrievalRequest(
                query=query,
                mode=mode,
                filters=filters or {},
                top_k=top_k,
                candidate_k=candidate_k,
            )
        )

    def clear(self, filters: dict[str, Any] | None = None) -> int:
        if not filters:
            raise ValueError("clear requires at least one exact-match filter")
        ids = self.store.list_ids(filters)
        self.store.delete(ids)
        return len(ids)


def _validate_document_scope(
    documents: list[KnowledgeDocument], scope: dict[str, Any]
) -> None:
    for document in documents:
        for field, expected in scope.items():
            actual = document.id if field == "document_id" else document.metadata.get(field)
            if actual != expected:
                raise ValueError(
                    f"Document {document.id!r} does not match sync scope "
                    f"{field}={expected!r}"
                )
