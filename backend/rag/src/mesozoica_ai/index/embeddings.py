from __future__ import annotations

import logging
import time

from collections.abc import Callable
from typing import TypeVar

from langchain_core.embeddings import Embeddings

from mesozoica_ai.common.errors import EmbeddingProviderError
from mesozoica_ai.common.models import EmbeddedChunk, KnowledgeChunk

logger = logging.getLogger(__name__)

T = TypeVar("T")


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
        vectors = self._with_retry(
            lambda: self.client.embed_documents(
                [chunk.embedding_text for chunk in chunks]
            )
        )
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
        logger.debug(
            "embed %s chunks (%s dims, %.0fms)",
            len(chunks),
            self.dimensions,
            (time.perf_counter() - started) * 1000,
        )
        return embedded

    def embed_query(self, query: str) -> list[float]:
        """Embed one retrieval query and validate its configured dimensions."""
        vector = self._with_retry(lambda: self.client.embed_query(query))
        if len(vector) != self.dimensions:
            raise RuntimeError(
                "Embedding provider returned a query vector with dimensions that do not "
                f"match the configured index ({self.dimensions})"
            )
        return vector

    def _with_retry(self, call: Callable[[], T], *, attempts: int = 8) -> T:
        """Retry Azure Foundry intermittent ``unknown_model`` 400s with backoff."""
        last_error: BaseException | None = None
        for attempt in range(1, attempts + 1):
            try:
                return call()
            except Exception as exc:
                last_error = exc
                if "unknown_model" not in str(exc) or attempt >= attempts:
                    if "unknown_model" in str(exc):
                        raise EmbeddingProviderError(
                            f"Azure OpenAI embedding deployment {self.model!r} "
                            f"unavailable after {attempts} attempts ({exc})"
                        ) from exc
                    raise
                delay = min(30.0, 0.5 * (2 ** (attempt - 1)))
                logger.debug(
                    "embed unknown_model from %s (attempt %s/%s); retrying in %.1fs",
                    self.model,
                    attempt,
                    attempts,
                    delay,
                )
                time.sleep(delay)
        assert last_error is not None
        raise last_error
