from azure.search.documents.indexes.models import (
    HnswAlgorithmConfiguration,
    SearchField,
    SearchFieldDataType,
    SearchIndex,
    SimpleField,
    SearchableField,
    VectorSearch,
    VectorSearchProfile,
)


class AzureKnowledgeIndex:
    def __init__(
        self,
        client,
        index_name: str,
        vector_dimensions: int = 1536,
    ):
        self.client = client
        self.index_name = index_name
        self.vector_dimensions = vector_dimensions

    def _definition(self) -> SearchIndex:
        fields = [
            SimpleField(
                name="id",
                type=SearchFieldDataType.String,
                key=True,
                filterable=True,
            ),
            SimpleField(
                name="source_id",
                type=SearchFieldDataType.String,
                filterable=True,
                facetable=True,
            ),
            SimpleField(
                name="content_hash",
                type=SearchFieldDataType.String,
            ),
            SearchableField(
                name="dinosaur",
                type=SearchFieldDataType.String,
                filterable=True,
                facetable=True,
            ),
            SearchableField(
                name="section",
                type=SearchFieldDataType.String,
                filterable=True,
                facetable=True,
            ),
            SearchableField(
                name="content",
                type=SearchFieldDataType.String,
            ),
            SimpleField(
                name="source_url",
                type=SearchFieldDataType.String,
            ),
            SearchField(
                name="embedding",
                type=SearchFieldDataType.Collection(
                    SearchFieldDataType.Single
                ),
                searchable=True,
                vector_search_dimensions=self.vector_dimensions,
                vector_search_profile_name="vector-profile",
            ),
        ]

        vector_search = VectorSearch(
            algorithms=[
                HnswAlgorithmConfiguration(
                    name="hnsw-config"
                )
            ],
            profiles=[
                VectorSearchProfile(
                    name="vector-profile",
                    algorithm_configuration_name="hnsw-config",
                )
            ],
        )

        return SearchIndex(
            name=self.index_name,
            fields=fields,
            vector_search=vector_search,
        )

    def ensure(self) -> None:
        self.client.create_or_update_index(
            self._definition()
        )

    def recreate(self) -> None:
        if self.index_name in self.client.list_index_names():
            self.client.delete_index(
                self.index_name
            )

        self.client.create_index(
            self._definition()
        )