from __future__ import annotations

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


class AzureKnowledgeIndex:
    REQUIRED_FIELDS = {
        "id",
        "namespace",
        "subject_id",
        "source",
        "source_id",
        "document_id",
        "title",
        "section",
        "content",
        "source_url",
        "published_at",
        "updated_at",
        "metadata_json",
        "content_hash",
        "chunk_index",
        "embedding",
    }

    def __init__(
        self,
        client,
        index_name: str,
        vector_dimensions: int = 1536,
        semantic_configuration_name: str = "knowledge-semantic",
    ) -> None:
        self.client = client
        self.index_name = index_name
        self.vector_dimensions = vector_dimensions
        self.semantic_configuration_name = semantic_configuration_name

    def definition(self) -> SearchIndex:
        filterable = {"namespace", "subject_id", "source", "source_id", "document_id"}
        fields = [
            SimpleField(
                name="id", type=SearchFieldDataType.String, key=True, filterable=True
            ),
            *[
                SimpleField(
                    name=name,
                    type=SearchFieldDataType.String,
                    filterable=True,
                    facetable=name in {"namespace", "source"},
                )
                for name in sorted(filterable)
            ],
            SearchableField(name="title", type=SearchFieldDataType.String),
            SearchableField(
                name="section",
                type=SearchFieldDataType.String,
                filterable=True,
                facetable=True,
            ),
            SearchableField(name="content", type=SearchFieldDataType.String),
            SimpleField(name="source_url", type=SearchFieldDataType.String),
            SimpleField(name="published_at", type=SearchFieldDataType.String),
            SimpleField(name="updated_at", type=SearchFieldDataType.String),
            SimpleField(name="metadata_json", type=SearchFieldDataType.String),
            SimpleField(name="content_hash", type=SearchFieldDataType.String),
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
                profiles=[
                    VectorSearchProfile(
                        name="knowledge-vector-profile",
                        algorithm_configuration_name="knowledge-hnsw",
                    )
                ],
            ),
            semantic_search=SemanticSearch(
                configurations=[
                    SemanticConfiguration(
                        name=self.semantic_configuration_name,
                        prioritized_fields=SemanticPrioritizedFields(
                            title_field=SemanticField(field_name="title"),
                            content_fields=[
                                SemanticField(field_name="content"),
                                SemanticField(field_name="section"),
                            ],
                        ),
                    )
                ]
            ),
        )

    def ensure(self) -> None:
        try:
            existing = self.client.get_index(self.index_name)
        except ResourceNotFoundError:
            self.client.create_index(self.definition())
            return
        fields = {field.name: field for field in existing.fields}
        missing = self.REQUIRED_FIELDS - set(fields)
        if missing:
            raise RuntimeError(
                "Azure Search index uses an incompatible schema; recreate it explicitly. "
                f"Missing fields: {', '.join(sorted(missing))}"
            )
        dimensions = getattr(fields["embedding"], "vector_search_dimensions", None)
        if dimensions != self.vector_dimensions:
            raise RuntimeError(
                "Azure Search embedding dimensions do not match configuration: "
                f"index={dimensions}, configured={self.vector_dimensions}"
            )
        invalid = []
        if not getattr(fields["id"], "key", False):
            invalid.append("id must be the key")
        filterable_fields = (
            "namespace",
            "subject_id",
            "source",
            "source_id",
            "document_id",
            "section",
        )
        for name in filterable_fields:
            if not getattr(fields[name], "filterable", False):
                invalid.append(f"{name} must be filterable")
        for name in ("title", "section", "content", "embedding"):
            if not getattr(fields[name], "searchable", False):
                invalid.append(f"{name} must be searchable")
        semantic = getattr(existing, "semantic_search", None)
        semantic_names = {
            configuration.name
            for configuration in (getattr(semantic, "configurations", None) or [])
        }
        if self.semantic_configuration_name not in semantic_names:
            invalid.append(
                f"semantic configuration {self.semantic_configuration_name!r} is missing"
            )
        if invalid:
            raise RuntimeError(
                "Azure Search index uses an incompatible schema; recreate it explicitly. "
                + "; ".join(invalid)
            )

    def recreate(self) -> None:
        try:
            self.client.delete_index(self.index_name)
        except ResourceNotFoundError:
            pass
        self.client.create_index(self.definition())
