"""normalize dinosaur_knowledge into source/doc/chunk

Revision ID: u0v1w2x3y4z5
Revises: t9u0v1w2x3y4
Create Date: 2026-08-11 09:30:00.000000
"""

from __future__ import annotations

import json
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "u0v1w2x3y4z5"
down_revision: Union[str, None] = "t9u0v1w2x3y4"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "dinosaur_knowledge_source",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("subject_kind", sa.String(length=32), nullable=False),
        sa.Column("subject_id", sa.String(length=64), nullable=False),
        sa.Column("subject_name", sa.String(length=255), nullable=False),
        sa.Column("source", sa.String(length=32), nullable=False),
        sa.Column("source_version", sa.String(length=255), nullable=True),
        sa.Column("source_hash", sa.String(length=64), nullable=True),
        sa.Column("content_hash", sa.String(length=64), nullable=True),
        sa.Column("embedded_hash", sa.String(length=64), nullable=True),
        sa.Column("embedded_pipeline_fingerprint", sa.String(length=64), nullable=True),
        sa.Column("indexed_hash", sa.String(length=64), nullable=True),
        sa.Column("indexed_pipeline_fingerprint", sa.String(length=64), nullable=True),
        sa.Column("acquisition_status", sa.String(length=16), nullable=False),
        sa.Column("embed_status", sa.String(length=16), nullable=False),
        sa.Column("index_status", sa.String(length=16), nullable=False),
        sa.Column("acquisition_attempts", sa.Integer(), nullable=False),
        sa.Column("embed_attempts", sa.Integer(), nullable=False),
        sa.Column("index_attempts", sa.Integer(), nullable=False),
        sa.Column("acquisition_error", sa.Text(), nullable=True),
        sa.Column("embed_error", sa.Text(), nullable=True),
        sa.Column("index_error", sa.Text(), nullable=True),
        sa.Column("acquisition_started_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("acquisition_finished_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("embed_started_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("embed_finished_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("index_started_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("index_finished_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("CURRENT_TIMESTAMP"),
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("CURRENT_TIMESTAMP"),
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "subject_kind",
            "subject_id",
            "source",
            name="uq_dinosaur_knowledge_source_subject_source",
        ),
    )
    for column in (
        "subject_kind",
        "subject_id",
        "subject_name",
        "source",
        "content_hash",
        "acquisition_status",
        "embed_status",
        "index_status",
    ):
        op.create_index(
            op.f(f"ix_dinosaur_knowledge_source_{column}"),
            "dinosaur_knowledge_source",
            [column],
            unique=False,
        )

    op.create_table(
        "dinosaur_knowledge_doc",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("source_id", sa.Integer(), nullable=False),
        sa.Column("document_id", sa.String(length=512), nullable=False),
        sa.Column("text", sa.Text(), nullable=False),
        sa.Column("doc_source", sa.String(length=32), nullable=False),
        sa.Column("provenance_source_id", sa.String(length=255), nullable=False),
        sa.Column("title", sa.String(length=1024), nullable=False),
        sa.Column("section", sa.String(length=1024), nullable=True),
        sa.Column("section_path", sa.JSON(), nullable=False),
        sa.Column("section_depth", sa.Integer(), nullable=True),
        sa.Column("section_ordinal", sa.Integer(), nullable=True),
        sa.Column("source_url", sa.String(length=2048), nullable=True),
        sa.Column("published_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("updated_at_source", sa.DateTime(timezone=True), nullable=True),
        sa.Column("namespace", sa.String(length=64), nullable=True),
        sa.Column("subject_id", sa.String(length=64), nullable=True),
        sa.Column("extra_metadata", sa.JSON(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("CURRENT_TIMESTAMP"),
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("CURRENT_TIMESTAMP"),
        ),
        sa.ForeignKeyConstraint(
            ["source_id"], ["dinosaur_knowledge_source.id"], ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "source_id",
            "document_id",
            name="uq_dinosaur_knowledge_doc_source_document",
        ),
    )
    for column in ("source_id", "document_id", "doc_source", "provenance_source_id"):
        op.create_index(
            op.f(f"ix_dinosaur_knowledge_doc_{column}"),
            "dinosaur_knowledge_doc",
            [column],
            unique=False,
        )

    op.create_table(
        "dinosaur_knowledge_chunk",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("source_id", sa.Integer(), nullable=False),
        sa.Column("document_id", sa.String(length=512), nullable=False),
        sa.Column("chunk_id", sa.String(length=512), nullable=False),
        sa.Column("chunk_index", sa.Integer(), nullable=False),
        sa.Column("start_index", sa.Integer(), nullable=False),
        sa.Column("text", sa.Text(), nullable=False),
        sa.Column("embedding_text", sa.Text(), nullable=False),
        sa.Column("embedding", sa.JSON(), nullable=False),
        sa.Column("embedding_hash", sa.String(length=64), nullable=False),
        sa.Column("document_hash", sa.String(length=64), nullable=False),
        sa.Column("pipeline_fingerprint", sa.String(length=64), nullable=False),
        sa.Column("metadata_json", sa.JSON(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("CURRENT_TIMESTAMP"),
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("CURRENT_TIMESTAMP"),
        ),
        sa.ForeignKeyConstraint(
            ["source_id"], ["dinosaur_knowledge_source.id"], ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "source_id",
            "chunk_id",
            name="uq_dinosaur_knowledge_chunk_source_chunk",
        ),
    )
    for column in (
        "source_id",
        "document_id",
        "chunk_id",
        "embedding_hash",
        "pipeline_fingerprint",
    ):
        op.create_index(
            op.f(f"ix_dinosaur_knowledge_chunk_{column}"),
            "dinosaur_knowledge_chunk",
            [column],
            unique=False,
        )

    _backfill_from_legacy()
    op.drop_table("dinosaur_knowledge")


def _backfill_from_legacy() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if "dinosaur_knowledge" not in inspector.get_table_names():
        return

    rows = bind.execute(sa.text("SELECT * FROM dinosaur_knowledge")).mappings().all()
    for row in rows:
        result = bind.execute(
            sa.text(
                """
                INSERT INTO dinosaur_knowledge_source (
                    subject_kind, subject_id, subject_name, source,
                    source_version, source_hash, content_hash,
                    embedded_hash, embedded_pipeline_fingerprint,
                    indexed_hash, indexed_pipeline_fingerprint,
                    acquisition_status, embed_status, index_status,
                    acquisition_attempts, embed_attempts, index_attempts,
                    acquisition_error, embed_error, index_error,
                    acquisition_started_at, acquisition_finished_at,
                    embed_started_at, embed_finished_at,
                    index_started_at, index_finished_at,
                    created_at, updated_at
                ) VALUES (
                    :subject_kind, :subject_id, :subject_name, :source,
                    :source_version, :source_hash, :content_hash,
                    :embedded_hash, :embedded_pipeline_fingerprint,
                    :indexed_hash, :indexed_pipeline_fingerprint,
                    :acquisition_status, :embed_status, :index_status,
                    :acquisition_attempts, :embed_attempts, :index_attempts,
                    :acquisition_error, :embed_error, :index_error,
                    :acquisition_started_at, :acquisition_finished_at,
                    :embed_started_at, :embed_finished_at,
                    :index_started_at, :index_finished_at,
                    :created_at, :updated_at
                ) RETURNING id
                """
            ),
            {
                "subject_kind": row["subject_kind"],
                "subject_id": row["subject_id"],
                "subject_name": row["subject_name"],
                "source": row["source"],
                "source_version": row.get("source_version"),
                "source_hash": row.get("source_hash"),
                "content_hash": row.get("content_hash"),
                "embedded_hash": row.get("embedded_hash"),
                "embedded_pipeline_fingerprint": row.get(
                    "embedded_pipeline_fingerprint"
                ),
                "indexed_hash": row.get("indexed_hash"),
                "indexed_pipeline_fingerprint": row.get("indexed_pipeline_fingerprint"),
                "acquisition_status": row["acquisition_status"],
                "embed_status": row.get("embed_status") or "pending",
                "index_status": row["index_status"],
                "acquisition_attempts": row["acquisition_attempts"],
                "embed_attempts": row.get("embed_attempts") or 0,
                "index_attempts": row["index_attempts"],
                "acquisition_error": row.get("acquisition_error"),
                "embed_error": row.get("embed_error"),
                "index_error": row.get("index_error"),
                "acquisition_started_at": row.get("acquisition_started_at"),
                "acquisition_finished_at": row.get("acquisition_finished_at"),
                "embed_started_at": row.get("embed_started_at"),
                "embed_finished_at": row.get("embed_finished_at"),
                "index_started_at": row.get("index_started_at"),
                "index_finished_at": row.get("index_finished_at"),
                "created_at": row["created_at"],
                "updated_at": row["updated_at"],
            },
        )
        source_pk = result.scalar_one()

        documents = row.get("documents") or []
        if isinstance(documents, str):
            documents = json.loads(documents)
        for document in documents:
            metadata = document.get("metadata") or {}
            known = {
                "source",
                "source_id",
                "source_version",
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
            extra = {k: v for k, v in metadata.items() if k not in known}
            bind.execute(
                sa.text(
                    """
                    INSERT INTO dinosaur_knowledge_doc (
                        source_id, document_id, text, doc_source,
                        provenance_source_id, title, section, section_path,
                        section_depth, section_ordinal, source_url,
                        published_at, updated_at_source, namespace, subject_id,
                        extra_metadata
                    ) VALUES (
                        :source_id, :document_id, :text, :doc_source,
                        :provenance_source_id, :title, :section,
                        CAST(:section_path AS json),
                        :section_depth, :section_ordinal, :source_url,
                        :published_at, :updated_at_source, :namespace, :subject_id,
                        CAST(:extra_metadata AS json)
                    )
                    """
                ),
                {
                    "source_id": source_pk,
                    "document_id": str(document.get("id") or ""),
                    "text": str(document.get("text") or ""),
                    "doc_source": str(metadata.get("source") or row["source"]),
                    "provenance_source_id": str(metadata.get("source_id") or ""),
                    "title": str(metadata.get("title") or ""),
                    "section": metadata.get("section"),
                    "section_path": json.dumps(metadata.get("section_path") or []),
                    "section_depth": metadata.get("section_depth"),
                    "section_ordinal": metadata.get("section_ordinal"),
                    "source_url": metadata.get("source_url"),
                    "published_at": metadata.get("published_at"),
                    "updated_at_source": metadata.get("updated_at"),
                    "namespace": metadata.get("namespace"),
                    "subject_id": metadata.get("subject_id"),
                    "extra_metadata": json.dumps(extra),
                },
            )

        chunks = row.get("embedded_chunks") or []
        if isinstance(chunks, str):
            chunks = json.loads(chunks)
        for chunk in chunks:
            metadata = chunk.get("metadata") or {}
            bind.execute(
                sa.text(
                    """
                    INSERT INTO dinosaur_knowledge_chunk (
                        source_id, document_id, chunk_id, chunk_index, start_index,
                        text, embedding_text, embedding, embedding_hash,
                        document_hash, pipeline_fingerprint, metadata_json
                    ) VALUES (
                        :source_id, :document_id, :chunk_id, :chunk_index, :start_index,
                        :text, :embedding_text, CAST(:embedding AS json), :embedding_hash,
                        :document_hash, :pipeline_fingerprint, CAST(:metadata_json AS json)
                    )
                    """
                ),
                {
                    "source_id": source_pk,
                    "document_id": str(chunk.get("document_id") or ""),
                    "chunk_id": str(chunk.get("id") or ""),
                    "chunk_index": int(chunk.get("chunk_index") or 0),
                    "start_index": int(chunk.get("start_index") or 0),
                    "text": str(chunk.get("text") or ""),
                    "embedding_text": str(chunk.get("embedding_text") or ""),
                    "embedding": json.dumps(chunk.get("embedding") or []),
                    "embedding_hash": str(chunk.get("embedding_hash") or ""),
                    "document_hash": str(chunk.get("document_hash") or ""),
                    "pipeline_fingerprint": str(
                        chunk.get("pipeline_fingerprint") or ""
                    ),
                    "metadata_json": json.dumps(metadata),
                },
            )


def downgrade() -> None:
    # Destructive reverse: recreate empty legacy table without restoring blobs.
    op.create_table(
        "dinosaur_knowledge",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("subject_kind", sa.String(length=32), nullable=False),
        sa.Column("subject_id", sa.String(length=64), nullable=False),
        sa.Column("subject_name", sa.String(length=255), nullable=False),
        sa.Column("source", sa.String(length=32), nullable=False),
        sa.Column("documents", sa.JSON(), nullable=False),
        sa.Column("embedded_chunks", sa.JSON(), nullable=False),
        sa.Column("source_version", sa.String(length=255), nullable=True),
        sa.Column("source_hash", sa.String(length=64), nullable=True),
        sa.Column("content_hash", sa.String(length=64), nullable=True),
        sa.Column("embedded_hash", sa.String(length=64), nullable=True),
        sa.Column("embedded_pipeline_fingerprint", sa.String(length=64), nullable=True),
        sa.Column("indexed_hash", sa.String(length=64), nullable=True),
        sa.Column("indexed_pipeline_fingerprint", sa.String(length=64), nullable=True),
        sa.Column("acquisition_status", sa.String(length=16), nullable=False),
        sa.Column("embed_status", sa.String(length=16), nullable=False),
        sa.Column("index_status", sa.String(length=16), nullable=False),
        sa.Column("acquisition_attempts", sa.Integer(), nullable=False),
        sa.Column("embed_attempts", sa.Integer(), nullable=False),
        sa.Column("index_attempts", sa.Integer(), nullable=False),
        sa.Column("acquisition_error", sa.Text(), nullable=True),
        sa.Column("embed_error", sa.Text(), nullable=True),
        sa.Column("index_error", sa.Text(), nullable=True),
        sa.Column("acquisition_started_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("acquisition_finished_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("embed_started_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("embed_finished_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("index_started_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("index_finished_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("CURRENT_TIMESTAMP"),
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("CURRENT_TIMESTAMP"),
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "subject_kind",
            "subject_id",
            "source",
            name="uq_dinosaur_knowledge_subject_source",
        ),
    )
    op.drop_table("dinosaur_knowledge_chunk")
    op.drop_table("dinosaur_knowledge_doc")
    op.drop_table("dinosaur_knowledge_source")
