from typing import Any, Protocol

from azure.search.documents import SearchClient
from azure.search.documents.models import VectorizedQuery

from .models import EmbeddedChunk, RetrievedChunk


class KnowledgeStore(Protocol):
    def list_ids(
        self,
        filters: dict[str, Any],
    ) -> list[str]:
        ...

    def upsert(
        self,
        chunks: list[EmbeddedChunk],
    ) -> None:
        ...

    def search(
        self,
        query: str,
        query_vector: list[float],
        mode: str = "hybrid",
        filters: dict[str, Any] | None = None,
        top_k: int = 5,
    ) -> list[RetrievedChunk]:
        ...

    def delete(
        self,
        ids: list[str],
    ) -> None:
        ...

    def get_content_hashes(
        self,
        filters: dict[str, Any],
    ) -> dict[str, str | None]:
        ...

class AzureSearchKnowledgeStore:
    def __init__(
        self,
        client: SearchClient,
        *,
        key_field: str = "id",
        text_field: str = "content",
        vector_field: str = "embedding",
        metadata_fields: tuple[str, ...] = (),
        filterable_fields: tuple[str, ...] = (),
    ):
        self.client = client
        self.key_field = key_field
        self.text_field = text_field
        self.vector_field = vector_field
        self.metadata_fields = metadata_fields
        self.filterable_fields = filterable_fields

    def upsert(
        self,
        chunks: list[EmbeddedChunk],
    ) -> None:

        if not chunks:
            return

        documents = []

        for chunk in chunks:
            document = {
                self.key_field: chunk.id,
                self.text_field: chunk.text,
                self.vector_field: chunk.embedding,
            }
            if chunk.content_hash:
                document["content_hash"] = chunk.content_hash

            for field in self.metadata_fields:
                if field in chunk.metadata:
                    document[field] = chunk.metadata[field]

            documents.append(document)

        results = self.client.upload_documents(
            documents=documents,
        )

        failures = [
            result
            for result in results
            if not result.succeeded
        ]

        if failures:
            errors = ", ".join(
                f"{r.key}: {r.error_message}"
                for r in failures
            )
            raise RuntimeError(
                f"Failed to index documents: {errors}"
            )

    def search(
        self,
        query: str,
        query_vector: list[float],
        mode: str = "hybrid",
        filters: dict[str, Any] | None = None,
        top_k: int = 5,
    ) -> list[RetrievedChunk]:

        search_text = (
            query
            if mode in ("keyword", "hybrid")
            else None
        )
        
        # Vector component
        vector_queries = None
        if mode in ("vector", "hybrid"):
            if query_vector is None:
                raise ValueError(
                    f"{mode} search requires a query vector"
                )
            vector_queries = [
                VectorizedQuery(
                    vector=query_vector,
                    k_nearest_neighbors=top_k,
                    fields=self.vector_field,
                )
            ]

        results = self.client.search(
            search_text=search_text,
            vector_queries=vector_queries,
            filter=self._build_filter(filters),
            select=[
                self.key_field,
                self.text_field,
                *self.metadata_fields,
            ],
            top=top_k,
        )

        return [
            RetrievedChunk(
                id=result[self.key_field],
                text=result[self.text_field],
                metadata={
                    field: result.get(field)
                    for field in self.metadata_fields
                    if result.get(field) is not None
                },
                score=result["@search.score"],
            )
            for result in results
        ]

    def delete(
        self,
        ids: list[str],
    ) -> None:

        if not ids:
            return

        self.client.delete_documents(
            documents=[
                {self.key_field: id_}
                for id_ in ids
            ]
        )

    def list_ids(
        self,
        filters: dict[str, Any],
    ) -> list[str]:

        results = self.client.search(
            search_text="*",
            filter=self._build_filter(filters),
            select=[self.key_field],
        )

        return [
            result[self.key_field]
            for result in results
        ]

    def _build_filter(
        self,
        filters: dict[str, Any] | None,
    ) -> str | None:

        if not filters:
            return None

        expressions = []

        for field, value in filters.items():

            if field not in self.filterable_fields:
                raise ValueError(
                    f"Field is not filterable: {field}"
                )

            if isinstance(value, str):
                value = value.replace("'", "''")
                expressions.append(
                    f"{field} eq '{value}'"
                )

            elif isinstance(value, bool):
                expressions.append(
                    f"{field} eq {str(value).lower()}"
                )

            else:
                expressions.append(
                    f"{field} eq {value}"
                )

        return " and ".join(expressions)

    def get_content_hashes(
        self,
        filters: dict[str, Any],
    ) -> dict[str, str | None]:

        results = self.client.search(
            search_text="*",
            filter=self._build_filter(filters),
            select=[
                self.key_field,
                "content_hash",
            ],
        )

        return {
            result[self.key_field]: result.get("content_hash")
            for result in results
        }