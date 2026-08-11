"""add dinosaur_knowledge embed stage columns

Revision ID: t9u0v1w2x3y4
Revises: s8t9u0v1w2x3
Create Date: 2026-08-11 08:00:00.000000
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "t9u0v1w2x3y4"
down_revision: Union[str, None] = "s8t9u0v1w2x3"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "dinosaur_knowledge",
        sa.Column(
            "embedded_chunks",
            sa.JSON(),
            nullable=False,
            server_default=sa.text("'[]'::json"),
        ),
    )
    op.add_column(
        "dinosaur_knowledge",
        sa.Column("embedded_hash", sa.String(length=64), nullable=True),
    )
    op.add_column(
        "dinosaur_knowledge",
        sa.Column("embedded_pipeline_fingerprint", sa.String(length=64), nullable=True),
    )
    op.add_column(
        "dinosaur_knowledge",
        sa.Column(
            "embed_status",
            sa.String(length=16),
            nullable=False,
            server_default="pending",
        ),
    )
    op.add_column(
        "dinosaur_knowledge",
        sa.Column(
            "embed_attempts",
            sa.Integer(),
            nullable=False,
            server_default="0",
        ),
    )
    op.add_column(
        "dinosaur_knowledge",
        sa.Column("embed_error", sa.Text(), nullable=True),
    )
    op.add_column(
        "dinosaur_knowledge",
        sa.Column("embed_started_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        "dinosaur_knowledge",
        sa.Column("embed_finished_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index(
        op.f("ix_dinosaur_knowledge_embed_status"),
        "dinosaur_knowledge",
        ["embed_status"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index(
        op.f("ix_dinosaur_knowledge_embed_status"),
        table_name="dinosaur_knowledge",
    )
    op.drop_column("dinosaur_knowledge", "embed_finished_at")
    op.drop_column("dinosaur_knowledge", "embed_started_at")
    op.drop_column("dinosaur_knowledge", "embed_error")
    op.drop_column("dinosaur_knowledge", "embed_attempts")
    op.drop_column("dinosaur_knowledge", "embed_status")
    op.drop_column("dinosaur_knowledge", "embedded_pipeline_fingerprint")
    op.drop_column("dinosaur_knowledge", "embedded_hash")
    op.drop_column("dinosaur_knowledge", "embedded_chunks")
