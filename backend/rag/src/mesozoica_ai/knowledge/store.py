"""Azure Search persistence with exact filters and resilient partial batch writes."""

from __future__ import annotations

import json
import logging
import random
import time
from collections.abc import Callable, Iterable
from datetime import datetime
from typing import Any, Protocol

from azure.search.documents import SearchClient
from azure.search.documents.models import VectorizedQuery
from azure.core.exceptions import HttpResponseError

from .errors import BatchWriteError
from .models import (
    ChunkState,
    EmbeddedChunk,
    KnowledgeChunk,
    RetrievalMode,
    RetrievalRequest,
    RetrievedChunk,
    SourceMetadata,
)


PROMOTED_METADATA_FIELDS = (
    "namespace",
    "subject_id",
    "source",
    "source_id",
    "title",
    "section",
    "source_url",
    "published_at",
    "updated_at",
)
FILTERABLE_FIELDS = frozenset(
    {"id", "namespace", "subject_id", "source", "source_id", "document_id", "section"}
)
TRANSIENT_STATUS_CODES = frozenset({408, 429, 500, 502, 503, 504})
logger = logging.getLogger(__name__)


class KnowledgeStore(Protocol):
    """Storage operations required by :class:`KnowledgeBase`."""

    def list_ids(self, filters: dict[str, Any]) -> list[str]:
        """List chunk IDs in one exact filter scope."""
        ...

    def upsert(self, chunks: list[EmbeddedChunk]) -> None:
        """Upload complete embedded chunks."""
        ...

    def merge_metadata(self, chunks: list[KnowledgeChunk]) -> None:
        """Merge stored fields while retaining vectors."""
        ...

    def search(
        self, *, request: RetrievalRequest, query_vector: list[float] | None
    ) -> list[RetrievedChunk]:
        """Execute one explicit retrieval request."""
        ...

    def delete(self, ids: list[str]) -> None:
        """Delete exact chunk IDs."""
        ...

    def get_chunk_states(self, filters: dict[str, Any]) -> dict[str, ChunkState]:
        """Read indexed hash state for safe synchronization."""
        ...


class AzureSearchKnowledgeStore:
    """Read/write adapter for the generic Azure AI Search index."""

    def __init__(
        self,
        *,
        query_client: SearchClient,
        write_client: SearchClient | None,
        semantic_configuration_name: str = "knowledge-semantic",
        write_batch_size: int = 250,
        write_batch_bytes: int = 8_000_000,
        write_attempts: int = 4,
        sleeper: Callable[[float], None] = time.sleep,
        jitter: Callable[[], float] = random.random,
    ) -> None:
        self.query_client = query_client
        self.write_client = write_client
        self.semantic_configuration_name = semantic_configuration_name
        self.write_batch_size = write_batch_size
        self.write_batch_bytes = write_batch_bytes
        self.write_attempts = write_attempts
        self.sleeper = sleeper
        self.jitter = jitter

    def upsert(self, chunks: list[EmbeddedChunk]) -> None:
        """Upload full documents and retry only transient per-document failures."""
        write_client = self._require_write_client()
        documents = [self._to_search_document(chunk, include_embedding=True) for chunk in chunks]
        self._write("upload", documents, write_client.upload_documents)

    def merge_metadata(self, chunks: list[KnowledgeChunk]) -> None:
        """Merge changed stored text/metadata without recomputing or replacing vectors."""
        write_client = self._require_write_client()
        documents = [self._to_search_document(chunk, include_embedding=False) for chunk in chunks]
        self._write("merge", documents, write_client.merge_documents)

    def search(
        self, *, request: RetrievalRequest, query_vector: list[float] | None
    ) -> list[RetrievedChunk]:
        """Execute exactly the requested Azure retrieval mode without fallback."""
        uses_text = request.mode in {
            RetrievalMode.KEYWORD,
            RetrievalMode.HYBRID,
            RetrievalMode.SEMANTIC_HYBRID,
        }
        uses_vector = request.mode in {
            RetrievalMode.VECTOR,
            RetrievalMode.HYBRID,
            RetrievalMode.SEMANTIC_HYBRID,
        }
        if uses_vector and query_vector is None:
            raise ValueError(f"{request.mode.value} search requires a query vector")
        vector_queries = (
            [
                VectorizedQuery(
                    vector=query_vector,
                    k_nearest_neighbors=request.candidate_k,
                    fields="embedding",
                )
            ]
            if uses_vector
            else None
        )
        kwargs: dict[str, Any] = {}
        if request.mode == RetrievalMode.SEMANTIC_HYBRID:
            kwargs.update(
                query_type="semantic",
                semantic_configuration_name=self.semantic_configuration_name,
            )
        results = self.query_client.search(
            search_text=request.query if uses_text else None,
            vector_queries=vector_queries,
            filter=build_filter(request.filters),
            select=[
                "id",
                "document_id",
                "content",
                "embedding_hash",
                "document_hash",
                "pipeline_fingerprint",
                "chunk_index",
                "metadata_json",
                *PROMOTED_METADATA_FIELDS,
            ],
            top=request.fetch_k,
            **kwargs,
        )
        return [self._from_search_result(result) for result in results]

    def delete(self, ids: list[str]) -> None:
        """Delete exact chunk keys with transient partial retry."""
        write_client = self._require_write_client()
        self._write(
            "delete",
            [{"id": identifier} for identifier in ids],
            write_client.delete_documents,
        )

    def _require_write_client(self) -> SearchClient:
        if self.write_client is None:
            from .errors import KnowledgeBaseConfigurationError

            raise KnowledgeBaseConfigurationError(
                "AZURE_SEARCH_ADMIN_KEY is required for index synchronization"
            )
        return self.write_client

    def list_ids(self, filters: dict[str, Any]) -> list[str]:
        """List chunk keys within an exact scope."""
        results = self.query_client.search(
            search_text="*", filter=build_filter(filters), select=["id"]
        )
        return [result["id"] for result in results]

    def get_chunk_states(self, filters: dict[str, Any]) -> dict[str, ChunkState]:
        """Read only hashes needed to classify incremental writes."""
        results = self.query_client.search(
            search_text="*",
            filter=build_filter(filters),
            select=["id", "embedding_hash", "document_hash", "pipeline_fingerprint"],
        )
        return {
            result["id"]: ChunkState(
                embedding_hash=result.get("embedding_hash"),
                document_hash=result.get("document_hash"),
                pipeline_fingerprint=result.get("pipeline_fingerprint"),
            )
            for result in results
        }

    def _write(
        self,
        operation: str,
        documents: list[dict[str, Any]],
        send: Callable[..., Iterable[Any]],
    ) -> None:
        for batch in _payload_batches(
            documents, max_count=self.write_batch_size, max_bytes=self.write_batch_bytes
        ):
            pending = batch
            permanent: list[str] = []
            for attempt in range(1, self.write_attempts + 1):
                by_key = {str(document["id"]): document for document in pending}
                try:
                    results = list(send(documents=pending))
                except HttpResponseError as exc:
                    status = getattr(exc, "status_code", None) or getattr(
                        getattr(exc, "response", None), "status_code", None
                    )
                    if status in TRANSIENT_STATUS_CODES and attempt < self.write_attempts:
                        self.sleeper(
                            min(8.0, 0.5 * 2 ** (attempt - 1)) + self.jitter() * 0.25
                        )
                        continue
                    raise BatchWriteError(operation, sorted(by_key)) from exc
                transient: list[dict[str, Any]] = []
                returned_keys: set[str] = set()
                for result in results:
                    returned_keys.add(str(result.key))
                    if result.succeeded:
                        continue
                    key = str(result.key)
                    status = getattr(result, "status_code", None)
                    if status in TRANSIENT_STATUS_CODES and key in by_key:
                        transient.append(by_key[key])
                    else:
                        permanent.append(key)
                # A missing per-document result is ambiguous and must not be counted as
                # success; retry that key without replaying confirmed successes.
                transient.extend(
                    by_key[key] for key in sorted(set(by_key) - returned_keys)
                )
                if permanent:
                    raise BatchWriteError(operation, sorted(set(permanent)))
                if not transient:
                    break
                if attempt == self.write_attempts:
                    raise BatchWriteError(
                        operation, sorted(str(document["id"]) for document in transient)
                    )
                pending = transient
                self.sleeper(min(8.0, 0.5 * 2 ** (attempt - 1)) + self.jitter() * 0.25)
            logger.info("rag.index.batch", extra={"rag": {
                "operation": operation, "document_count": len(batch),
            }})

    @staticmethod
    def _to_search_document(
        chunk: KnowledgeChunk | EmbeddedChunk, *, include_embedding: bool
    ) -> dict[str, Any]:
        metadata = chunk.metadata.model_dump(mode="json", exclude_none=True)
        document: dict[str, Any] = {
            "id": chunk.id,
            "document_id": chunk.document_id,
            "content": chunk.text,
            "embedding_hash": chunk.embedding_hash,
            "document_hash": chunk.document_hash,
            "pipeline_fingerprint": chunk.pipeline_fingerprint,
            "schema_version": "2",
            "chunk_index": chunk.chunk_index,
            "metadata_json": json.dumps(metadata, ensure_ascii=False, default=str),
        }
        if include_embedding:
            document["embedding"] = chunk.embedding
        for field in PROMOTED_METADATA_FIELDS:
            # Explicit nulls clear values during merge; omission would retain stale
            # promoted metadata even though metadata_json had already changed.
            document[field] = metadata.get(field)
        return document

    @staticmethod
    def _from_search_result(result: Any) -> RetrievedChunk:
        try:
            metadata = json.loads(result.get("metadata_json") or "{}")
        except (TypeError, json.JSONDecodeError):
            metadata = {}
        for field in PROMOTED_METADATA_FIELDS:
            value = result.get(field)
            if isinstance(value, datetime):
                value = value.isoformat()
            if value is not None:
                metadata[field] = value
        return RetrievedChunk(
            id=result["id"],
            document_id=result["document_id"],
            text=result["content"],
            metadata=SourceMetadata.model_validate(metadata),
            chunk_index=int(result.get("chunk_index") or 0),
            embedding_hash=result.get("embedding_hash"),
            document_hash=result.get("document_hash"),
            pipeline_fingerprint=result.get("pipeline_fingerprint"),
            score=float(result.get("@search.score") or 0.0),
            reranker_score=(
                float(result["@search.reranker_score"])
                if result.get("@search.reranker_score") is not None
                else None
            ),
        )


def build_filter(filters: dict[str, Any] | None) -> str | None:
    """Build an allow-listed OData expression containing exact matches only."""
    if not filters:
        return None
    expressions: list[str] = []
    for field, value in filters.items():
        if field not in FILTERABLE_FIELDS:
            raise ValueError(f"Field is not filterable: {field}")
        if isinstance(value, str):
            expressions.append(f"{field} eq '{value.replace(chr(39), chr(39) * 2)}'")
        elif isinstance(value, bool):
            expressions.append(f"{field} eq {str(value).lower()}")
        elif isinstance(value, (int, float)):
            expressions.append(f"{field} eq {value}")
        elif value is None:
            expressions.append(f"{field} eq null")
        else:
            raise TypeError(f"Unsupported filter value for {field}: {type(value).__name__}")
    return " and ".join(expressions)


def _payload_batches(
    documents: Iterable[dict[str, Any]], *, max_count: int, max_bytes: int
) -> Iterable[list[dict[str, Any]]]:
    """Batch under both Azure's document-count and estimated JSON payload limits."""
    batch: list[dict[str, Any]] = []
    size = 0
    for document in documents:
        document_size = len(
            json.dumps(document, ensure_ascii=False, default=str, separators=(",", ":")).encode(
                "utf-8"
            )
        )
        if document_size > max_bytes:
            raise BatchWriteError("payload_too_large", [str(document.get("id", "unknown"))])
        if batch and (len(batch) >= max_count or size + document_size > max_bytes):
            yield batch
            batch = []
            size = 0
        batch.append(document)
        size += document_size
    if batch:
        yield batch
