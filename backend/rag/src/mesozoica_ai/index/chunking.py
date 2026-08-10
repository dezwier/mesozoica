"""Section-preserving exact-token chunking with deterministic fingerprints."""

from __future__ import annotations

import hashlib
import json
import logging
import time

from langchain_core.documents import Document
from langchain_text_splitters import RecursiveCharacterTextSplitter

from mesozoica_ai.common.models import KnowledgeChunk, KnowledgeDocument
from mesozoica_ai.common.tokens import TokenCounter

logger = logging.getLogger(__name__)


def _digest(value: object) -> str:
    return hashlib.sha256(
        json.dumps(value, sort_keys=True, ensure_ascii=False, default=str).encode("utf-8")
    ).hexdigest()


class RecursiveChunker:
    """Split within source documents while retaining their section provenance."""

    VERSION = "token-recursive-v2"

    def __init__(
        self,
        *,
        token_counter: TokenCounter,
        chunk_size: int = 500,
        chunk_overlap: int = 75,
        embedding_deployment: str,
        embedding_dimensions: int,
        index_schema_version: str,
    ) -> None:
        if chunk_overlap >= chunk_size:
            raise ValueError("chunk_overlap must be smaller than chunk_size")
        self.token_counter = token_counter
        self.chunk_size = chunk_size
        self.chunk_overlap = chunk_overlap
        self.embedding_deployment = embedding_deployment
        self.embedding_dimensions = embedding_dimensions
        self.index_schema_version = index_schema_version
        self.splitter = RecursiveCharacterTextSplitter(
            chunk_size=chunk_size,
            chunk_overlap=chunk_overlap,
            add_start_index=True,
            separators=["\n\n", "\n", ". ", " ", ""],
            length_function=token_counter.count,
        )

    @property
    def pipeline_fingerprint(self) -> str:
        """Identify every input that can alter chunk or vector compatibility."""
        return _digest(
            {
                "index_schema_version": self.index_schema_version,
                "chunker_version": self.VERSION,
                "chunk_size": self.chunk_size,
                "chunk_overlap": self.chunk_overlap,
                "embedding_encoding": self.token_counter.encoding_name,
                "embedding_deployment": self.embedding_deployment,
                "embedding_dimensions": self.embedding_dimensions,
            }
        )

    def split(self, documents: list[KnowledgeDocument]) -> list[KnowledgeChunk]:
        """Produce stable chunks and separate embedding/storage hashes."""
        started = time.perf_counter()
        chunks: list[KnowledgeChunk] = []
        for document in documents:
            metadata = document.metadata.model_dump(mode="json", exclude_none=True)
            pieces = self.splitter.split_documents(
                [Document(page_content=document.text, metadata=metadata)]
            )
            for chunk_index, piece in enumerate(pieces):
                text = piece.page_content.strip()
                if not text:
                    continue
                piece_metadata = dict(piece.metadata)
                start_index = max(0, int(piece_metadata.pop("start_index", 0)))
                title = str(piece_metadata.get("title") or "").strip()
                path = piece_metadata.get("section_path") or []
                section = " > ".join(str(item) for item in path) or str(
                    piece_metadata.get("section") or ""
                ).strip()
                prefix = " — ".join(item for item in (title, section) if item)
                embedding_text = f"{prefix}\n\n{text}" if prefix else text

                # Identity excludes mutable metadata so metadata-only updates can merge.
                chunk_id = _digest(
                    {
                        "document_id": document.id,
                        "start_index": start_index,
                        "chunk_index": chunk_index,
                        "text": text,
                        "chunker_version": self.VERSION,
                    }
                )
                embedding_hash = _digest(
                    {
                        "embedding_text": embedding_text,
                        "deployment": self.embedding_deployment,
                        "dimensions": self.embedding_dimensions,
                        "encoding": self.token_counter.encoding_name,
                        "chunker_version": self.VERSION,
                    }
                )
                document_hash = _digest(
                    {
                        "document_id": document.id,
                        "text": text,
                        "embedding_text": embedding_text,
                        "metadata": piece_metadata,
                        "start_index": start_index,
                        "chunk_index": chunk_index,
                    }
                )
                chunks.append(
                    KnowledgeChunk(
                        id=chunk_id,
                        document_id=document.id,
                        text=text,
                        embedding_text=embedding_text,
                        metadata=piece_metadata,
                        chunk_index=chunk_index,
                        start_index=start_index,
                        embedding_hash=embedding_hash,
                        document_hash=document_hash,
                        pipeline_fingerprint=self.pipeline_fingerprint,
                    )
                )
        logger.debug(
            "chunked %s docs → %s chunks (%.0fms)",
            len(documents),
            len(chunks),
            (time.perf_counter() - started) * 1000,
        )
        return chunks
