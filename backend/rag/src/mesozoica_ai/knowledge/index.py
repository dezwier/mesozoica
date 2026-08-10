"""Generic Azure AI Search index definition and strict compatibility checks."""

from __future__ import annotations

import logging
from azure.core.exceptions import ResourceNotFoundError
from azure.search.documents.indexes.models import (
    HnswAlgorithmConfiguration,
    SearchField,
    SearchFieldDataType,
    SearchIndex,
    SearchableField,
    SemanticConfiguration,
    SemanticField,
    SemanticPrioritizedFields,
    SemanticSearch,
    SimpleField,
    VectorSearch,
    VectorSearchProfile,
)

from .errors import IndexCompatibilityError

logger = logging.getLogger(__name__)


class AzureKnowledgeIndex:
    """Create a missing index or reject incompatible existing infrastructure."""

    SCHEMA_VERSION = "2"
    REQUIRED_FIELDS = {
        "id", "namespace", "subject_id", "source", "source_id", "document_id",
        "title", "section", "content", "source_url", "published_at", "updated_at",
        "metadata_json", "embedding_hash", "document_hash", "pipeline_fingerprint",
        "schema_version", "chunk_index", "embedding",
    }

    def __init__(self, client, index_name: str, vector_dimensions: int = 1536,
                 semantic_configuration_name: str = "knowledge-semantic") -> None:
        self.client = client
        self.index_name = index_name
        self.vector_dimensions = vector_dimensions
        self.semantic_configuration_name = semantic_configuration_name

    def definition(self) -> SearchIndex:
        """Build the authoritative schema without creating remote resources."""
        filterable = {"namespace", "subject_id", "source", "source_id", "document_id"}
        fields = [
            SimpleField(name="id", type=SearchFieldDataType.String, key=True, filterable=True),
            *[
                SimpleField(name=name, type=SearchFieldDataType.String, filterable=True,
                            facetable=name in {"namespace", "source"})
                for name in sorted(filterable)
            ],
            SearchableField(name="title", type=SearchFieldDataType.String),
            SearchableField(name="section", type=SearchFieldDataType.String,
                            filterable=True, facetable=True),
            SearchableField(name="content", type=SearchFieldDataType.String),
            SimpleField(name="source_url", type=SearchFieldDataType.String),
            SimpleField(name="published_at", type=SearchFieldDataType.DateTimeOffset),
            SimpleField(name="updated_at", type=SearchFieldDataType.DateTimeOffset),
            SimpleField(name="metadata_json", type=SearchFieldDataType.String),
            SimpleField(name="embedding_hash", type=SearchFieldDataType.String),
            SimpleField(name="document_hash", type=SearchFieldDataType.String),
            SimpleField(name="pipeline_fingerprint", type=SearchFieldDataType.String,
                        filterable=True),
            SimpleField(name="schema_version", type=SearchFieldDataType.String,
                        filterable=True),
            SimpleField(name="chunk_index", type=SearchFieldDataType.Int32),
            SearchField(
                name="embedding",
                type=SearchFieldDataType.Collection(SearchFieldDataType.Single),
                searchable=True,
                vector_search_dimensions=self.vector_dimensions,
                vector_search_profile_name="knowledge-vector-profile",
            ),
        ]
        return SearchIndex(
            name=self.index_name,
            fields=fields,
            vector_search=VectorSearch(
                algorithms=[HnswAlgorithmConfiguration(name="knowledge-hnsw")],
                profiles=[VectorSearchProfile(
                    name="knowledge-vector-profile",
                    algorithm_configuration_name="knowledge-hnsw",
                )],
            ),
            semantic_search=SemanticSearch(configurations=[SemanticConfiguration(
                name=self.semantic_configuration_name,
                prioritized_fields=SemanticPrioritizedFields(
                    title_field=SemanticField(field_name="title"),
                    content_fields=[SemanticField(field_name="content"),
                                    SemanticField(field_name="section")],
                ),
            )]),
        )

    def ensure(self) -> None:
        """Create only when missing; never silently mutate an existing index."""
        try:
            existing = self.client.get_index(self.index_name)
        except ResourceNotFoundError:
            self.client.create_index(self.definition())
            logger.info("rag.index.create", extra={"rag": {
                "index": self.index_name, "schema_version": self.SCHEMA_VERSION,
                "dimensions": self.vector_dimensions,
            }})
            return
        fields = {field.name: field for field in existing.fields}
        invalid: list[str] = []
        missing = self.REQUIRED_FIELDS - set(fields)
        if missing:
            invalid.append(f"missing fields: {', '.join(sorted(missing))}")
        if "embedding" in fields and getattr(fields["embedding"], "vector_search_dimensions", None) != self.vector_dimensions:
            invalid.append(
                "embedding dimensions differ "
                f"(index={getattr(fields['embedding'], 'vector_search_dimensions', None)}, "
                f"configured={self.vector_dimensions})"
            )
        if "id" in fields and not getattr(fields["id"], "key", False):
            invalid.append("id must be the key")
        for name in ("namespace", "subject_id", "source", "source_id", "document_id",
                     "section", "pipeline_fingerprint", "schema_version"):
            if name in fields and not getattr(fields[name], "filterable", False):
                invalid.append(f"{name} must be filterable")
        for name in ("title", "section", "content", "embedding"):
            if name in fields and not getattr(fields[name], "searchable", False):
                invalid.append(f"{name} must be searchable")
        for name in ("published_at", "updated_at"):
            if name in fields and fields[name].type != SearchFieldDataType.DateTimeOffset:
                invalid.append(f"{name} must use Edm.DateTimeOffset")
        semantic = getattr(existing, "semantic_search", None)
        names = {item.name for item in (getattr(semantic, "configurations", None) or [])}
        if self.semantic_configuration_name not in names:
            invalid.append(f"semantic configuration {self.semantic_configuration_name!r} is missing")
        if invalid:
            raise IndexCompatibilityError(
                "Azure Search index is incompatible; use explicit --recreate-index. "
                + "; ".join(invalid)
            )
        logger.info("rag.index.validate", extra={"rag": {
            "index": self.index_name, "schema_version": self.SCHEMA_VERSION,
            "dimensions": self.vector_dimensions,
        }})

    def recreate(self) -> None:
        """Destructively replace the index; callers must expose this explicitly."""
        try:
            self.client.delete_index(self.index_name)
        except ResourceNotFoundError:
            pass
        self.client.create_index(self.definition())
        logger.warning("rag.index.recreate", extra={"rag": {
            "index": self.index_name, "schema_version": self.SCHEMA_VERSION,
            "dimensions": self.vector_dimensions,
        }})

    def inspect_pipeline_fingerprints(self, query_client) -> set[str]:
        """Return fingerprints currently represented by indexed chunks."""
        results = query_client.search(
            search_text="*", select=["pipeline_fingerprint"]
        )
        return {result["pipeline_fingerprint"] for result in results if result.get("pipeline_fingerprint")}
