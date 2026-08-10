"""Private construction of Azure and LangChain knowledge components."""

from azure.core.credentials import AzureKeyCredential
from azure.search.documents import SearchClient
from azure.search.documents.indexes import SearchIndexClient
from langchain_openai import OpenAIEmbeddings

from .chunking import RecursiveChunker
from mesozoica_ai.common.config import AiConfig as KnowledgeConfig
from .embeddings import Embedder
from mesozoica_ai.common.errors import ConfigurationError as KnowledgeBaseConfigurationError
from .schema import AzureKnowledgeIndex
from .store import AzureSearchKnowledgeStore
from mesozoica_ai.common.tokens import TokenCounter


def build_chunker(config: KnowledgeConfig) -> RecursiveChunker:
    """Build the deterministic chunker represented by ``config``."""
    return RecursiveChunker(
        token_counter=TokenCounter(config.embedding_encoding),
        chunk_size=config.chunk_size,
        chunk_overlap=config.chunk_overlap,
        embedding_deployment=config.embedding_deployment,
        embedding_dimensions=config.embedding_dimensions,
        index_schema_version=AzureKnowledgeIndex.SCHEMA_VERSION,
    )


def build_embedder(config: KnowledgeConfig) -> Embedder:
    """Build the configured Azure OpenAI embedding adapter."""
    client = OpenAIEmbeddings(
        model=config.embedding_deployment,
        base_url=config.openai_v1_base_url,
        api_key=config.openai_api_key.get_secret_value(),
        dimensions=config.embedding_dimensions,
        chunk_size=config.embedding_batch_size,
        tiktoken_enabled=True,
        tiktoken_model_name=config.embedding_encoding,
    )
    return Embedder(
        client=client,
        model=config.embedding_deployment,
        dimensions=config.embedding_dimensions,
    )


def build_store(
    config: KnowledgeConfig, *, write_enabled: bool
) -> AzureSearchKnowledgeStore:
    """Build a read-only or write-capable Azure Search store."""
    query_key = config.search_query_key
    if query_key is None or not query_key.get_secret_value().strip():
        raise KnowledgeBaseConfigurationError(
            "AZURE_SEARCH_QUERY_KEY is required "
            "(or set AZURE_SEARCH_ADMIN_KEY / AZURE_SEARCH_API_KEY for local fallback)"
        )
    query_client = SearchClient(
        endpoint=config.search_endpoint,
        index_name=config.search_index,
        credential=AzureKeyCredential(query_key.get_secret_value()),
    )
    if write_enabled and config.search_admin_key is None:
        raise KnowledgeBaseConfigurationError(
            "AZURE_SEARCH_ADMIN_KEY is required for knowledge writes"
        )
    write_client = (
        SearchClient(
            endpoint=config.search_endpoint,
            index_name=config.search_index,
            credential=AzureKeyCredential(config.search_admin_key.get_secret_value()),
        )
        if write_enabled and config.search_admin_key is not None
        else None
    )
    return AzureSearchKnowledgeStore(
        query_client=query_client,
        write_client=write_client,
        semantic_configuration_name=config.semantic_configuration_name,
        write_batch_size=config.write_batch_size,
        write_batch_bytes=config.write_batch_bytes,
        write_attempts=config.write_attempts,
    )


def build_index(config: KnowledgeConfig) -> AzureKnowledgeIndex:
    """Build an index manager using the Search admin key."""
    if config.search_admin_key is None:
        raise KnowledgeBaseConfigurationError(
            "AZURE_SEARCH_ADMIN_KEY is required for index management"
        )
    client = SearchIndexClient(
        endpoint=config.search_endpoint,
        credential=AzureKeyCredential(config.search_admin_key.get_secret_value()),
    )
    return AzureKnowledgeIndex(
        client=client,
        index_name=config.search_index,
        vector_dimensions=config.embedding_dimensions,
        semantic_configuration_name=config.semantic_configuration_name,
    )
