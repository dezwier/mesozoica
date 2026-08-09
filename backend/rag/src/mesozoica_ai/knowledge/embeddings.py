from openai import OpenAI

from .models import KnowledgeChunk, EmbeddedChunk


class Embedder:
    def __init__(
        self,
        client: OpenAI,
        model: str,
    ):
        self.client = client
        self.model = model

    def embed(
        self,
        chunks: list[KnowledgeChunk],
    ) -> list[EmbeddedChunk]:

        if not chunks:
            return []

        response = self.client.embeddings.create(
            model=self.model,
            input=[chunk.text for chunk in chunks],
        )

        return [
            EmbeddedChunk(
                **chunk.model_dump(),
                embedding=result.embedding,
            )
            for chunk, result in zip(
                chunks,
                response.data,
            )
        ]

    def embed_query(
        self,
        query: str,
    ) -> list[float]:

        response = self.client.embeddings.create(
            model=self.model,
            input=query,
        )

        return response.data[0].embedding