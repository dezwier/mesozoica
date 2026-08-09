from __future__ import annotations

from azure.core.credentials import AzureKeyCredential
from azure.search.documents import SearchClient
from azure.search.documents.indexes import SearchIndexClient
from langchain_openai import ChatOpenAI, OpenAIEmbeddings

from mesozoica_ai.generation import StructuredRag

from .base import KnowledgeBase
from .chunking import RecursiveChunker
from .embeddings import Embedder
from .index import AzureKnowledgeIndex
from .inspection import KnowledgeInspector
from .settings import KnowledgeSettings
from .store import AzureSearchKnowledgeStore


def _base_url(settings: KnowledgeSettings) -> str:
    endpoint = settings.openai_endpoint.rstrip("/")
    if endpoint.endswith("/openai/v1"):
        return endpoint + "/"
    return endpoint + "/openai/v1/"


def create_knowledge_index(settings: KnowledgeSettings) -> AzureKnowledgeIndex:
    client = SearchIndexClient(
        endpoint=settings.search_endpoint,
        credential=AzureKeyCredential(settings.search_api_key.get_secret_value()),
    )
    return AzureKnowledgeIndex(
        client=client,
        index_name=settings.search_index,
        vector_dimensions=settings.embedding_dimensions,
        semantic_configuration_name=settings.semantic_configuration_name,
    )


def create_knowledge_base(settings: KnowledgeSettings) -> KnowledgeBase:
    embeddings = OpenAIEmbeddings(
        model=settings.embedding_model,
        base_url=_base_url(settings),
        api_key=settings.openai_api_key.get_secret_value(),
        dimensions=settings.embedding_dimensions,
    )
    search_client = SearchClient(
        endpoint=settings.search_endpoint,
        index_name=settings.search_index,
        credential=AzureKeyCredential(settings.search_api_key.get_secret_value()),
    )
    return KnowledgeBase(
        chunker=RecursiveChunker(
            chunk_size=settings.chunk_size,
            chunk_overlap=settings.chunk_overlap,
            embedding_model=settings.embedding_model,
            embedding_dimensions=settings.embedding_dimensions,
        ),
        embedder=Embedder(
            client=embeddings,
            model=settings.embedding_model,
            dimensions=settings.embedding_dimensions,
        ),
        store=AzureSearchKnowledgeStore(
            client=search_client,
            semantic_configuration_name=settings.semantic_configuration_name,
        ),
    )


def create_structured_rag(settings: KnowledgeSettings) -> StructuredRag:
    if not settings.chat_model.strip():
        raise ValueError("AZURE_OPENAI_CHAT_DEPLOYMENT is required for structured RAG")
    llm = ChatOpenAI(
        model=settings.chat_model,
        base_url=_base_url(settings),
        api_key=settings.openai_api_key.get_secret_value(),
        temperature=0,
    )
    return StructuredRag(
        knowledge_base=create_knowledge_base(settings),
        llm=llm,
        context_token_budget=settings.context_token_budget,
    )


def create_knowledge_inspector(settings: KnowledgeSettings) -> KnowledgeInspector:
    client = SearchClient(
        endpoint=settings.search_endpoint,
        index_name=settings.search_index,
        credential=AzureKeyCredential(settings.search_api_key.get_secret_value()),
    )
    return KnowledgeInspector(client)
