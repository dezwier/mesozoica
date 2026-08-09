"""add resumable RAG source snapshots

Revision ID: q6r7s8t9u0v1
Revises: p5q6r7s8t9u0
Create Date: 2026-08-09 18:00:00.000000

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "q6r7s8t9u0v1"
down_revision: Union[str, None] = "p5q6r7s8t9u0"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "rag_source_snapshot",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("subject_kind", sa.String(length=32), nullable=False),
        sa.Column("subject_id", sa.String(length=64), nullable=False),
        sa.Column("subject_name", sa.String(length=255), nullable=False),
        sa.Column("source", sa.String(length=32), nullable=False),
        sa.Column("documents", sa.JSON(), nullable=False),
        sa.Column("source_version", sa.String(length=255), nullable=True),
        sa.Column("source_hash", sa.String(length=64), nullable=True),
        sa.Column("content_hash", sa.String(length=64), nullable=True),
        sa.Column("indexed_hash", sa.String(length=64), nullable=True),
        sa.Column("acquisition_status", sa.String(length=16), nullable=False),
        sa.Column("index_status", sa.String(length=16), nullable=False),
        sa.Column("acquisition_attempts", sa.Integer(), nullable=False),
        sa.Column("index_attempts", sa.Integer(), nullable=False),
        sa.Column("acquisition_error", sa.Text(), nullable=True),
        sa.Column("index_error", sa.Text(), nullable=True),
        sa.Column("acquisition_started_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("acquisition_finished_at", sa.DateTime(timezone=True), nullable=True),
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
            name="uq_rag_source_snapshot_subject_source",
        ),
    )
    for column in (
        "subject_kind",
        "subject_id",
        "subject_name",
        "source",
        "content_hash",
        "acquisition_status",
        "index_status",
    ):
        op.create_index(
            op.f(f"ix_rag_source_snapshot_{column}"),
            "rag_source_snapshot",
            [column],
            unique=False,
        )


def downgrade() -> None:
    for column in reversed(
        (
            "subject_kind",
            "subject_id",
            "subject_name",
            "source",
            "content_hash",
            "acquisition_status",
            "index_status",
        )
    ):
        op.drop_index(
            op.f(f"ix_rag_source_snapshot_{column}"),
            table_name="rag_source_snapshot",
        )
    op.drop_table("rag_source_snapshot")
