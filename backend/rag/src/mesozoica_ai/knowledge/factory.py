from openai import OpenAI
from azure.core.credentials import AzureKeyCredential
from azure.search.documents import SearchClient
from azure.search.documents.indexes import SearchIndexClient

from .index import AzureKnowledgeIndex
from .base import KnowledgeBase
from .chunking import RecursiveChunker
from .embeddings import Embedder
from .settings import KnowledgeSettings
from .store import AzureSearchKnowledgeStore
from .inspection import KnowledgeInspector


def create_knowledge_index(
    settings: KnowledgeSettings,
) -> AzureKnowledgeIndex:

    client = SearchIndexClient(
        endpoint=settings.search_endpoint,
        credential=AzureKeyCredential(
            settings.search_api_key.get_secret_value()
        ),
    )

    return AzureKnowledgeIndex(
        client=client,
        index_name=settings.search_index,
    )

def create_knowledge_base(
    settings: KnowledgeSettings,
) -> KnowledgeBase:

    openai_client = OpenAI(
        api_key=settings.openai_api_key.get_secret_value(),
        base_url=(
            settings.openai_endpoint.rstrip("/")
            + "/openai/v1/"
        ),
    )

    search_client = SearchClient(
        endpoint=settings.search_endpoint,
        index_name=settings.search_index,
        credential=AzureKeyCredential(
            settings.search_api_key.get_secret_value()
        ),
    )

    return KnowledgeBase(
        chunker=RecursiveChunker(
            chunk_size=settings.chunk_size,
            chunk_overlap=settings.chunk_overlap,
        ),
        embedder=Embedder(
            client=openai_client,
            model=settings.embedding_model,
        ),
        store=AzureSearchKnowledgeStore(
            client=search_client,
            metadata_fields=(
                "source_id",
                "dinosaur",
                "section",
                "source_url",
            ),
            filterable_fields=(
                "source_id",
                "dinosaur",
                "section",
            ),
        ),
    )

def create_knowledge_inspector(
    settings: KnowledgeSettings,
) -> KnowledgeInspector:

    client = SearchClient(
        endpoint=settings.search_endpoint,
        index_name=settings.search_index,
        credential=AzureKeyCredential(
            settings.search_api_key.get_secret_value()
        ),
    )

    return KnowledgeInspector(client)