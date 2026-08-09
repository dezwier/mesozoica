import os

from dotenv import load_dotenv
from azure.core.credentials import AzureKeyCredential
from azure.search.documents.indexes import SearchIndexClient
from azure.search.documents.indexes.models import (
    SearchIndex,
    SimpleField,
    SearchableField,
    SearchField,
    SearchFieldDataType,
    VectorSearch,
    HnswAlgorithmConfiguration,
    VectorSearchProfile,
)


load_dotenv()

endpoint = os.environ["AZURE_SEARCH_ENDPOINT"]
api_key = os.environ["AZURE_SEARCH_API_KEY"]

INDEX_NAME = "dinosaur-knowledge"
VECTOR_DIMENSIONS = 1536


index_client = SearchIndexClient(
    endpoint=endpoint,
    credential=AzureKeyCredential(api_key),
)


fields = [
    SimpleField(
        name="id",
        type=SearchFieldDataType.String,
        key=True,
        filterable=True,
    ),

    SearchableField(
        name="dinosaur",
        type=SearchFieldDataType.String,
        filterable=True,
    ),

    SearchableField(
        name="section",
        type=SearchFieldDataType.String,
        filterable=True,
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
        type=SearchFieldDataType.Collection(SearchFieldDataType.Single),
        searchable=True,
        vector_search_dimensions=VECTOR_DIMENSIONS,
        vector_search_profile_name="vector-profile",
    ),
]


vector_search = VectorSearch(
    algorithms=[
        HnswAlgorithmConfiguration(
            name="hnsw-config",
        )
    ],
    profiles=[
        VectorSearchProfile(
            name="vector-profile",
            algorithm_configuration_name="hnsw-config",
        )
    ],
)


index = SearchIndex(
    name=INDEX_NAME,
    fields=fields,
    vector_search=vector_search,
)


result = index_client.create_or_update_index(index)

print(f"Index created: {result.name}")