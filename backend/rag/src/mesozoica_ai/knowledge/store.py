from __future__ import annotations

import json
from collections.abc import Iterable
from typing import Any, Protocol

from azure.search.documents import SearchClient
from azure.search.documents.models import VectorizedQuery

from .models import EmbeddedChunk, RetrievalRequest, RetrievedChunk, SearchMode


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


class KnowledgeStore(Protocol):
    def list_ids(self, filters: dict[str, Any]) -> list[str]: ...

    def upsert(self, chunks: list[EmbeddedChunk]) -> None: ...

    def search(
        self, *, request: RetrievalRequest, query_vector: list[float] | None
    ) -> list[RetrievedChunk]: ...

    def delete(self, ids: list[str]) -> None: ...

    def get_content_hashes(self, filters: dict[str, Any]) -> dict[str, str | None]: ...


class AzureSearchKnowledgeStore:
    def __init__(
        self,
        client: SearchClient,
        *,
        semantic_configuration_name: str = "knowledge-semantic",
        upload_batch_size: int = 500,
    ) -> None:
        self.client = client
        self.semantic_configuration_name = semantic_configuration_name
        self.upload_batch_size = upload_batch_size

    def upsert(self, chunks: list[EmbeddedChunk]) -> None:
        for batch in _batches(chunks, self.upload_batch_size):
            documents = [self._to_search_document(chunk) for chunk in batch]
            failures = [
                result
                for result in self.client.upload_documents(documents=documents)
                if not result.succeeded
            ]
            if failures:
                errors = ", ".join(
                    f"{result.key}: {result.error_message}" for result in failures
                )
                raise RuntimeError(f"Failed to index documents: {errors}")

    def search(
        self, *, request: RetrievalRequest, query_vector: list[float] | None
    ) -> list[RetrievedChunk]:
        uses_text = request.mode in {
            SearchMode.KEYWORD,
            SearchMode.HYBRID,
            SearchMode.SEMANTIC_HYBRID,
        }
        uses_vector = request.mode in {
            SearchMode.VECTOR,
            SearchMode.HYBRID,
            SearchMode.SEMANTIC_HYBRID,
        }
        if uses_vector and query_vector is None:
            raise ValueError(f"{request.mode} search requires a query vector")
        vector_queries = None
        if uses_vector:
            vector_queries = [
                VectorizedQuery(
                    vector=query_vector,
                    k_nearest_neighbors=request.candidate_k,
                    fields="embedding",
                )
            ]
        kwargs: dict[str, Any] = {}
        if request.mode == SearchMode.SEMANTIC_HYBRID:
            kwargs.update(
                query_type="semantic",
                semantic_configuration_name=self.semantic_configuration_name,
            )
        results = self.client.search(
            search_text=request.query if uses_text else None,
            vector_queries=vector_queries,
            filter=build_filter(request.filters),
            select=[
                "id",
                "document_id",
                "content",
                "content_hash",
                "chunk_index",
                "metadata_json",
                *PROMOTED_METADATA_FIELDS,
            ],
            top=request.top_k,
            **kwargs,
        )
        return [self._from_search_result(result) for result in results]

    def delete(self, ids: list[str]) -> None:
        for batch in _batches(ids, self.upload_batch_size):
            results = self.client.delete_documents(
                documents=[{"id": identifier} for identifier in batch]
            )
            failures = [result for result in results if not result.succeeded]
            if failures:
                raise RuntimeError(
                    "Failed to delete documents: "
                    + ", ".join(
                        f"{result.key}: {result.error_message}" for result in failures
                    )
                )

    def list_ids(self, filters: dict[str, Any]) -> list[str]:
        results = self.client.search(
            search_text="*", filter=build_filter(filters), select=["id"]
        )
        return [result["id"] for result in results]

    def get_content_hashes(self, filters: dict[str, Any]) -> dict[str, str | None]:
        results = self.client.search(
            search_text="*",
            filter=build_filter(filters),
            select=["id", "content_hash"],
        )
        return {result["id"]: result.get("content_hash") for result in results}

    @staticmethod
    def _to_search_document(chunk: EmbeddedChunk) -> dict[str, Any]:
        metadata = chunk.metadata.copy()
        document: dict[str, Any] = {
            "id": chunk.id,
            "document_id": chunk.document_id,
            "content": chunk.text,
            "embedding": chunk.embedding,
            "content_hash": chunk.content_hash,
            "chunk_index": chunk.chunk_index,
            "metadata_json": json.dumps(metadata, ensure_ascii=False, default=str),
        }
        for field in PROMOTED_METADATA_FIELDS:
            value = metadata.get(field)
            if value is not None:
                document[field] = str(value)
        return document

    @staticmethod
    def _from_search_result(result: Any) -> RetrievedChunk:
        raw_metadata = result.get("metadata_json") or "{}"
        try:
            metadata = json.loads(raw_metadata)
        except (TypeError, json.JSONDecodeError):
            metadata = {}
        for field in PROMOTED_METADATA_FIELDS:
            value = result.get(field)
            if value is not None:
                metadata[field] = value
        return RetrievedChunk(
            id=result["id"],
            document_id=result["document_id"],
            text=result["content"],
            metadata=metadata,
            chunk_index=int(result.get("chunk_index") or 0),
            content_hash=result.get("content_hash"),
            score=float(result.get("@search.score") or 0.0),
            reranker_score=(
                float(result["@search.reranker_score"])
                if result.get("@search.reranker_score") is not None
                else None
            ),
        )


def build_filter(filters: dict[str, Any] | None) -> str | None:
    if not filters:
        return None
    expressions: list[str] = []
    for field, value in filters.items():
        if field not in FILTERABLE_FIELDS:
            raise ValueError(f"Field is not filterable: {field}")
        if isinstance(value, str):
            escaped = value.replace("'", "''")
            expressions.append(f"{field} eq '{escaped}'")
        elif isinstance(value, bool):
            expressions.append(f"{field} eq {str(value).lower()}")
        elif isinstance(value, (int, float)):
            expressions.append(f"{field} eq {value}")
        elif value is None:
            expressions.append(f"{field} eq null")
        else:
            raise TypeError(f"Unsupported filter value for {field}: {type(value).__name__}")
    return " and ".join(expressions)


def _batches(items: Iterable[Any], size: int) -> Iterable[list[Any]]:
    batch: list[Any] = []
    for item in items:
        batch.append(item)
        if len(batch) >= size:
            yield batch
            batch = []
    if batch:
        yield batch
