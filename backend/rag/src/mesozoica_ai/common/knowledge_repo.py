"""Repository protocol and SQLModel implementation for normalized knowledge tables."""

from __future__ import annotations

from collections.abc import Sequence
from datetime import datetime, timezone
from typing import Any, Protocol

from mesozoica_ai.common.batch import DEFAULT_SUBJECT_KIND
from mesozoica_ai.common.checkpoints import (
    reset_embedding,
    reset_indexing,
)
from mesozoica_ai.common.models import Document, EmbeddedChunk, SourceMetadata


class KnowledgeRepository(Protocol):
    """Persistence surface for source / doc / chunk knowledge tables."""

    def get_or_create_source(
        self,
        *,
        subject: Any,
        source: str,
        subject_kind: str = DEFAULT_SUBJECT_KIND,
    ) -> Any: ...

    def get_source(
        self,
        *,
        subject_kind: str,
        subject_id: str,
        source: str,
    ) -> Any | None: ...

    def list_sources(
        self,
        *,
        subject_kind: str = DEFAULT_SUBJECT_KIND,
        names: list[str] | None = None,
        sources: list[str] | None = None,
        acquisition_succeeded_only: bool = False,
        max_items: int | None = None,
    ) -> list[Any]: ...

    def save_source(self, source_row: Any) -> None: ...

    def commit(self) -> None: ...

    def refresh(self, source_row: Any) -> Any: ...

    def list_documents(self, source_row: Any) -> list[Document]: ...

    def replace_documents(
        self,
        source_row: Any,
        documents: Sequence[Document],
        *,
        clear_chunks: bool,
    ) -> None: ...

    def delete_chunks(self, source_row: Any) -> None: ...

    def list_chunks(self, source_row: Any) -> list[EmbeddedChunk]: ...

    def replace_chunks(
        self, source_row: Any, chunks: Sequence[EmbeddedChunk]
    ) -> None: ...


class SqlModelKnowledgeRepository:
    """SQLModel-backed repository parameterized by the three table classes."""

    def __init__(
        self,
        session: Any,
        *,
        source_model: type[Any],
        doc_model: type[Any],
        chunk_model: type[Any],
    ) -> None:
        self.session = session
        self.source_model = source_model
        self.doc_model = doc_model
        self.chunk_model = chunk_model

    def get_or_create_source(
        self,
        *,
        subject: Any,
        source: str,
        subject_kind: str = DEFAULT_SUBJECT_KIND,
    ) -> Any:
        row = self.get_source(
            subject_kind=subject_kind,
            subject_id=str(subject.id),
            source=source,
        )
        if row is None:
            row = self.source_model(
                subject_kind=subject_kind,
                subject_id=str(subject.id),
                subject_name=subject.name,
                source=source,
            )
            self.session.add(row)
            self.session.commit()
            self.session.refresh(row)
        elif row.subject_name != subject.name:
            row.subject_name = subject.name
            self.session.add(row)
        return row

    def get_source(
        self,
        *,
        subject_kind: str,
        subject_id: str,
        source: str,
    ) -> Any | None:
        from sqlmodel import select

        return self.session.exec(
            select(self.source_model).where(
                self.source_model.subject_kind == subject_kind,
                self.source_model.subject_id == str(subject_id),
                self.source_model.source == source,
            )
        ).first()

    def list_sources(
        self,
        *,
        subject_kind: str = DEFAULT_SUBJECT_KIND,
        names: list[str] | None = None,
        sources: list[str] | None = None,
        acquisition_succeeded_only: bool = False,
        max_items: int | None = None,
    ) -> list[Any]:
        from sqlmodel import col, select

        statement = (
            select(self.source_model)
            .where(self.source_model.subject_kind == subject_kind)
            .order_by(
                col(self.source_model.subject_name),
                col(self.source_model.source),
            )
        )
        if acquisition_succeeded_only:
            statement = statement.where(
                self.source_model.acquisition_status == "succeeded"
            )
        if sources:
            statement = statement.where(col(self.source_model.source).in_(list(sources)))
        rows = list(self.session.exec(statement).all())
        if names:
            wanted = {name.strip().casefold() for name in names if name.strip()}
            rows = [row for row in rows if row.subject_name.casefold() in wanted]
        if max_items is not None:
            rows = rows[:max_items]
        return rows

    def save_source(self, source_row: Any) -> None:
        source_row.updated_at = datetime.now(timezone.utc)
        self.session.add(source_row)

    def commit(self) -> None:
        self.session.commit()

    def refresh(self, source_row: Any) -> Any:
        self.session.refresh(source_row)
        return source_row

    def list_documents(self, source_row: Any) -> list[Document]:
        from sqlmodel import col, select

        rows = list(
            self.session.exec(
                select(self.doc_model)
                .where(self.doc_model.source_id == source_row.id)
                .order_by(col(self.doc_model.id))
            ).all()
        )
        return [_doc_row_to_document(row) for row in rows]

    def replace_documents(
        self,
        source_row: Any,
        documents: Sequence[Document],
        *,
        clear_chunks: bool,
    ) -> None:
        from sqlmodel import delete

        self.session.exec(
            delete(self.doc_model).where(self.doc_model.source_id == source_row.id)
        )
        if clear_chunks:
            self.delete_chunks(source_row)
            reset_embedding(source_row)
            reset_indexing(source_row)
        now = datetime.now(timezone.utc)
        for document in documents:
            self.session.add(_document_to_doc_row(self.doc_model, source_row.id, document, now=now))
        self.save_source(source_row)

    def delete_chunks(self, source_row: Any) -> None:
        from sqlmodel import delete

        self.session.exec(
            delete(self.chunk_model).where(self.chunk_model.source_id == source_row.id)
        )

    def list_chunks(self, source_row: Any) -> list[EmbeddedChunk]:
        from sqlmodel import col, select

        rows = list(
            self.session.exec(
                select(self.chunk_model)
                .where(self.chunk_model.source_id == source_row.id)
                .order_by(col(self.chunk_model.chunk_index), col(self.chunk_model.id))
            ).all()
        )
        return [_chunk_row_to_embedded(row) for row in rows]

    def replace_chunks(
        self, source_row: Any, chunks: Sequence[EmbeddedChunk]
    ) -> None:
        self.delete_chunks(source_row)
        now = datetime.now(timezone.utc)
        for chunk in chunks:
            self.session.add(
                _embedded_to_chunk_row(self.chunk_model, source_row.id, chunk, now=now)
            )
        self.save_source(source_row)


def _document_to_doc_row(
    doc_model: type[Any], source_pk: int, document: Document, *, now: datetime
) -> Any:
    metadata = document.metadata
    known = {
        "source",
        "source_id",
        "title",
        "section",
        "section_path",
        "section_depth",
        "section_ordinal",
        "source_url",
        "published_at",
        "updated_at",
        "namespace",
        "subject_id",
    }
    dumped = metadata.model_dump(mode="json")
    extra = {key: value for key, value in dumped.items() if key not in known}
    return doc_model(
        source_id=source_pk,
        document_id=document.id,
        text=document.text,
        doc_source=metadata.source,
        provenance_source_id=metadata.source_id,
        title=metadata.title,
        section=metadata.section,
        section_path=list(metadata.section_path or []),
        section_depth=metadata.section_depth,
        section_ordinal=metadata.section_ordinal,
        source_url=metadata.source_url,
        published_at=metadata.published_at,
        updated_at_source=metadata.updated_at,
        namespace=metadata.namespace,
        subject_id=metadata.subject_id,
        extra_metadata=extra,
        created_at=now,
        updated_at=now,
    )


def _doc_row_to_document(row: Any) -> Document:
    metadata = {
        "source": row.doc_source,
        "source_id": row.provenance_source_id,
        "title": row.title,
        "section": row.section,
        "section_path": list(row.section_path or []),
        "section_depth": row.section_depth,
        "section_ordinal": row.section_ordinal,
        "source_url": row.source_url,
        "published_at": row.published_at,
        "updated_at": row.updated_at_source,
        "namespace": row.namespace,
        "subject_id": row.subject_id,
        **(row.extra_metadata or {}),
    }
    return Document(id=row.document_id, text=row.text, metadata=metadata)


def _embedded_to_chunk_row(
    chunk_model: type[Any],
    source_pk: int,
    chunk: EmbeddedChunk | dict[str, Any],
    *,
    now: datetime,
) -> Any:
    if isinstance(chunk, dict):
        chunk = EmbeddedChunk.model_validate(chunk)
    return chunk_model(
        source_id=source_pk,
        document_id=chunk.document_id,
        chunk_id=chunk.id,
        chunk_index=chunk.chunk_index,
        start_index=chunk.start_index,
        text=chunk.text,
        embedding_text=chunk.embedding_text,
        embedding=list(chunk.embedding),
        embedding_hash=chunk.embedding_hash,
        document_hash=chunk.document_hash,
        pipeline_fingerprint=chunk.pipeline_fingerprint,
        metadata_json=chunk.metadata.model_dump(mode="json"),
        created_at=now,
        updated_at=now,
    )


def _chunk_row_to_embedded(row: Any) -> EmbeddedChunk:
    return EmbeddedChunk(
        id=row.chunk_id,
        document_id=row.document_id,
        text=row.text,
        embedding_text=row.embedding_text,
        metadata=SourceMetadata.model_validate(row.metadata_json or {}),
        chunk_index=row.chunk_index,
        start_index=row.start_index,
        embedding_hash=row.embedding_hash,
        document_hash=row.document_hash,
        pipeline_fingerprint=row.pipeline_fingerprint,
        embedding=list(row.embedding or []),
    )
