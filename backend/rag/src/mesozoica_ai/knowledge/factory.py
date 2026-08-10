"""Factories for Azure-backed indexing and retrieval components."""

from __future__ import annotations

from azure.core.credentials import AzureKeyCredential
from azure.search.documents import SearchClient
from azure.search.documents.indexes import SearchIndexClient
from langchain_openai import OpenAIEmbeddings

from .errors import KnowledgeBaseConfigurationError
from .settings import KnowledgeBaseSettings
from .tokens import TokenCounter

from .service import KnowledgeBase
from .chunking import RecursiveChunker
from .embeddings import Embedder
from .index import AzureKnowledgeIndex
from .inspection import KnowledgeInspector
from .store import AzureSearchKnowledgeStore


def create_knowledge_index(settings: KnowledgeBaseSettings) -> AzureKnowledgeIndex:
    """Create an index manager using the write-capable Search admin key."""
    if settings.search_admin_key is None:
        raise KnowledgeBaseConfigurationError(
            "AZURE_SEARCH_ADMIN_KEY is required for index management"
        )
    client = SearchIndexClient(
        endpoint=settings.search_endpoint,
        credential=AzureKeyCredential(settings.search_admin_key.get_secret_value()),
    )
    return AzureKnowledgeIndex(
        client=client,
        index_name=settings.search_index,
        vector_dimensions=settings.embedding_dimensions,
        semantic_configuration_name=settings.semantic_configuration_name,
    )


def create_knowledge_base(
    settings: KnowledgeBaseSettings, *, write_enabled: bool = True
) -> KnowledgeBase:
    """Create the pipeline, optionally omitting all write-capable Search credentials."""
    embedding_counter = TokenCounter(settings.embedding_encoding)
    embeddings = OpenAIEmbeddings(
        model=settings.embedding_deployment,
        base_url=settings.openai_v1_base_url,
        api_key=settings.openai_api_key.get_secret_value(),
        dimensions=settings.embedding_dimensions,
        chunk_size=settings.embedding_batch_size,
        tiktoken_enabled=True,
        tiktoken_model_name=settings.embedding_encoding,
    )
    query_client = SearchClient(
        endpoint=settings.search_endpoint,
        index_name=settings.search_index,
        credential=AzureKeyCredential(settings.search_query_key.get_secret_value()),
    )
    if write_enabled and settings.search_admin_key is None:
        raise KnowledgeBaseConfigurationError(
            "AZURE_SEARCH_ADMIN_KEY is required when write_enabled=True"
        )
    write_client = (
        SearchClient(
            endpoint=settings.search_endpoint,
            index_name=settings.search_index,
            credential=AzureKeyCredential(settings.search_admin_key.get_secret_value()),
        )
        if settings.search_admin_key is not None and write_enabled
        else None
    )
    return KnowledgeBase(
        chunker=RecursiveChunker(
            token_counter=embedding_counter,
            chunk_size=settings.chunk_size,
            chunk_overlap=settings.chunk_overlap,
            embedding_deployment=settings.embedding_deployment,
            embedding_dimensions=settings.embedding_dimensions,
            index_schema_version=AzureKnowledgeIndex.SCHEMA_VERSION,
        ),
        embedder=Embedder(
            client=embeddings,
            model=settings.embedding_deployment,
            dimensions=settings.embedding_dimensions,
        ),
        store=AzureSearchKnowledgeStore(
            query_client=query_client,
            write_client=write_client,
            semantic_configuration_name=settings.semantic_configuration_name,
            write_batch_size=settings.write_batch_size,
            write_batch_bytes=settings.write_batch_bytes,
            write_attempts=settings.write_attempts,
        ),
    )


def create_knowledge_inspector(settings: KnowledgeBaseSettings) -> KnowledgeInspector:
    """Create a read-only index inspector with the Search query key."""
    client = SearchClient(
        endpoint=settings.search_endpoint,
        index_name=settings.search_index,
        credential=AzureKeyCredential(settings.search_query_key.get_secret_value()),
    )
    return KnowledgeInspector(client)
