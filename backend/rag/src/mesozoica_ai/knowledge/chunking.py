from __future__ import annotations

import hashlib
import json

from langchain_core.documents import Document
from langchain_text_splitters import RecursiveCharacterTextSplitter

from mesozoica_ai.tokens import count_tokens

from .models import KnowledgeChunk, KnowledgeDocument


class RecursiveChunker:
    """Section-preserving, token-aware splitter with deterministic chunk identity."""

    VERSION = "token-recursive-v1"

    def __init__(
        self,
        chunk_size: int = 500,
        chunk_overlap: int = 75,
        *,
        encoding_name: str = "unicode-word-v1",
        embedding_model: str = "unknown",
        embedding_dimensions: int = 1536,
    ) -> None:
        self.chunk_size = chunk_size
        self.chunk_overlap = chunk_overlap
        self.encoding_name = encoding_name
        self.embedding_model = embedding_model
        self.embedding_dimensions = embedding_dimensions
        self.splitter = RecursiveCharacterTextSplitter(
            chunk_size=chunk_size,
            chunk_overlap=chunk_overlap,
            add_start_index=True,
            separators=["\n\n", "\n", ". ", " ", ""],
            length_function=lambda text: count_tokens(
                text, encoding_name=self.encoding_name
            ),
        )

    @property
    def signature(self) -> str:
        return (
            f"{self.VERSION}:{self.encoding_name}:{self.chunk_size}:"
            f"{self.chunk_overlap}:{self.embedding_model}:{self.embedding_dimensions}"
        )

    def split(self, documents: list[KnowledgeDocument]) -> list[KnowledgeChunk]:
        chunks: list[KnowledgeChunk] = []
        for document in documents:
            langchain_document = Document(
                page_content=document.text,
                metadata=document.metadata.copy(),
            )
            pieces = self.splitter.split_documents([langchain_document])
            for chunk_index, piece in enumerate(pieces):
                text = piece.page_content.strip()
                if not text:
                    continue
                start_index = max(0, int(piece.metadata.pop("start_index", 0)))
                metadata = piece.metadata
                title = str(metadata.get("title") or "").strip()
                section = str(metadata.get("section") or "").strip()
                heading = " — ".join(value for value in (title, section) if value)
                embedding_text = f"{heading}\n\n{text}" if heading else text
                identity = f"{document.id}:{start_index}:{chunk_index}:{text}"
                chunk_id = hashlib.sha256(identity.encode("utf-8")).hexdigest()
                hash_payload = {
                    "document_id": document.id,
                    "text": text,
                    "embedding_text": embedding_text,
                    "metadata": metadata,
                    "chunker": self.signature,
                }
                content_hash = hashlib.sha256(
                    json.dumps(
                        hash_payload,
                        sort_keys=True,
                        ensure_ascii=False,
                        default=str,
                    ).encode("utf-8")
                ).hexdigest()
                chunks.append(
                    KnowledgeChunk(
                        id=chunk_id,
                        document_id=document.id,
                        text=text,
                        embedding_text=embedding_text,
                        metadata=metadata,
                        chunk_index=chunk_index,
                        start_index=start_index,
                        content_hash=content_hash,
                    )
                )
        return chunks
