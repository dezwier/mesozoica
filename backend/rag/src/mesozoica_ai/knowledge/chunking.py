from langchain_text_splitters import RecursiveCharacterTextSplitter

from .models import KnowledgeDocument, KnowledgeChunk


class RecursiveChunker:
    def __init__(
        self,
        chunk_size: int = 1000,
        chunk_overlap: int = 150,
    ):
        self.splitter = RecursiveCharacterTextSplitter(
            chunk_size=chunk_size,
            chunk_overlap=chunk_overlap,
        )

    def split(
        self,
        documents: list[KnowledgeDocument],
    ) -> list[KnowledgeChunk]:

        chunks = []

        for document in documents:
            texts = self.splitter.split_text(
                document.text
            )

            for i, text in enumerate(texts):
                chunks.append(
                    KnowledgeChunk(
                        id=f"{document.id}-{i:04d}",
                        text=text,
                        metadata=document.metadata.copy(),
                    )
                )

        return chunks