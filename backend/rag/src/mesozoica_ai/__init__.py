"""Mesozoica AI: callable RAG pipeline."""

from mesozoica_ai.common.config import AiConfig
from mesozoica_ai.generate import prompt_rag
from mesozoica_ai.index import (
    chunk_documents,
    embed_chunks,
    embed_query,
    ensure_index,
    index_chunks,
    retrieve_chunks,
    sync_documents,
)
from mesozoica_ai.sources import retrieve_openalex, retrieve_wikipedia

__all__ = [
    "AiConfig",
    "chunk_documents",
    "embed_chunks",
    "embed_query",
    "ensure_index",
    "index_chunks",
    "prompt_rag",
    "retrieve_chunks",
    "retrieve_openalex",
    "retrieve_wikipedia",
    "sync_documents",
]
