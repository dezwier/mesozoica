from __future__ import annotations

import logging
import time

from langchain_core.embeddings import Embeddings

from mesozoica_ai.common.models import EmbeddedChunk, KnowledgeChunk

logger = logging.getLogger(__name__)


class Embedder:
    """Validate embedding vector counts and dimensions around a LangChain client."""

    def __init__(self, client: Embeddings, model: str, dimensions: int) -> None:
        self.client = client
        self.model = model
        self.dimensions = dimensions

    def embed(self, chunks: list[KnowledgeChunk]) -> list[EmbeddedChunk]:
        """Embed chunk-specific contextual text and preserve clean stored evidence."""
        if not chunks:
            return []
        started = time.perf_counter()
        vectors = self.client.embed_documents([chunk.embedding_text for chunk in chunks])
        if len(vectors) != len(chunks):
            raise RuntimeError("Embedding provider returned an unexpected vector count")
        if any(len(vector) != self.dimensions for vector in vectors):
            raise RuntimeError(
                "Embedding provider returned vectors with dimensions that do not match "
                f"the configured index ({self.dimensions})"
            )
        embedded = [
            EmbeddedChunk(**chunk.model_dump(), embedding=vector)
            for chunk, vector in zip(chunks, vectors, strict=True)
        ]
        logger.info("rag.embed", extra={"rag": {
            "chunk_count": len(chunks), "dimensions": self.dimensions,
            "deployment": self.model,
            "duration_ms": (time.perf_counter() - started) * 1000,
        }})
        return embedded

    def embed_query(self, query: str) -> list[float]:
        """Embed one retrieval query and validate its configured dimensions."""
        vector = self.client.embed_query(query)
        if len(vector) != self.dimensions:
            raise RuntimeError(
                "Embedding provider returned a query vector with dimensions that do not "
                f"match the configured index ({self.dimensions})"
            )
        return vector
