from __future__ import annotations

from langchain_core.embeddings import Embeddings

from .models import EmbeddedChunk, KnowledgeChunk


class Embedder:
    def __init__(self, client: Embeddings, model: str, dimensions: int) -> None:
        self.client = client
        self.model = model
        self.dimensions = dimensions

    def embed(self, chunks: list[KnowledgeChunk]) -> list[EmbeddedChunk]:
        if not chunks:
            return []
        vectors = self.client.embed_documents([chunk.embedding_text for chunk in chunks])
        if len(vectors) != len(chunks):
            raise RuntimeError("Embedding provider returned an unexpected vector count")
        if any(len(vector) != self.dimensions for vector in vectors):
            raise RuntimeError(
                "Embedding provider returned vectors with dimensions that do not match "
                f"the configured index ({self.dimensions})"
            )
        return [
            EmbeddedChunk(**chunk.model_dump(), embedding=vector)
            for chunk, vector in zip(chunks, vectors, strict=True)
        ]

    def embed_query(self, query: str) -> list[float]:
        vector = self.client.embed_query(query)
        if len(vector) != self.dimensions:
            raise RuntimeError(
                "Embedding provider returned a query vector with dimensions that do not "
                f"match the configured index ({self.dimensions})"
            )
        return vector
