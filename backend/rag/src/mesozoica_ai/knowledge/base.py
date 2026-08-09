from typing import Any
import hashlib
import json

from .chunking import RecursiveChunker
from .embeddings import Embedder
from .models import (
    KnowledgeDocument,
    RetrievedChunk,
    IngestResult,
    SyncResult,
)
from .store import KnowledgeStore


class KnowledgeBase:
    def __init__(
        self,
        *,
        chunker: RecursiveChunker,
        embedder: Embedder,
        store: KnowledgeStore,
    ):
        self.chunker = chunker
        self.embedder = embedder
        self.store = store

    def ingest(
        self,
        documents: list[KnowledgeDocument],
    ) -> IngestResult:
        chunks = self.chunker.split(documents)
        embedded = self.embedder.embed(chunks)

        self.store.upsert(embedded)

        return IngestResult(
            document_count=len(documents),
            chunk_count=len(chunks),
            chunk_ids=[
                chunk.id
                for chunk in chunks
            ],
        )

    def sync(
        self,
        documents: list[KnowledgeDocument],
        *,
        scope: dict[str, Any],
    ) -> SyncResult:

        # Current source → chunks
        chunks = self.chunker.split(documents)

        # Generate deterministic fingerprints.
        for chunk in chunks:
            payload = {
                "text": chunk.text,
                "metadata": chunk.metadata,
                "embedding_model": self.embedder.model,
            }

            serialized = json.dumps(
                payload,
                sort_keys=True,
                ensure_ascii=False,
            )

            chunk.content_hash = hashlib.sha256(
                serialized.encode("utf-8")
            ).hexdigest()

        current = {
            chunk.id: chunk
            for chunk in chunks
        }

        # What does Azure currently contain?
        existing_hashes = self.store.get_content_hashes(
            scope
        )

        # Only embed new/changed chunks.
        changed_chunks = [
            chunk
            for chunk in chunks
            if existing_hashes.get(chunk.id)
            != chunk.content_hash
        ]

        embedded = self.embedder.embed(
            changed_chunks
        )

        self.store.upsert(embedded)

        # Delete chunks that disappeared.
        stale_ids = sorted(
            set(existing_hashes)
            - set(current)
        )

        self.store.delete(stale_ids)

        return SyncResult(
            document_count=len(documents),
            chunk_count=len(chunks),
            embedded_count=len(changed_chunks),
            skipped_count=(
                len(chunks)
                - len(changed_chunks)
            ),
            deleted_count=len(stale_ids),
            chunk_ids=sorted(current),
        )

    def search(
        self,
        query: str,
        *,
        mode: str = "hybrid",
        filters: dict[str, Any] | None = None,
        top_k: int = 5,
    ) -> list[RetrievedChunk]:

        query_vector = None
        if mode in ("vector", "hybrid"):
            query_vector = self.embedder.embed_query(
                query
            )

        return self.store.search(
            query=query,
            query_vector=query_vector,
            mode=mode,
            filters=filters,
            top_k=top_k,
        )

    def delete(
        self,
        chunk_ids: list[str],
    ) -> None:
        self.store.delete(chunk_ids)

    def clear(
        self,
        filters: dict[str, Any] | None = None,
    ) -> int:
        ids = self.store.list_ids(filters or {})
        self.store.delete(ids)
        return len(ids)