"""rename rag_source_snapshot to dinosaur_knowledge

Revision ID: s8t9u0v1w2x3
Revises: r7s8t9u0v1w2
Create Date: 2026-08-10 12:30:00.000000
"""

from typing import Sequence, Union

from alembic import op

revision: str = "s8t9u0v1w2x3"
down_revision: Union[str, None] = "r7s8t9u0v1w2"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_INDEXED_COLUMNS = (
    "subject_kind",
    "subject_id",
    "subject_name",
    "source",
    "content_hash",
    "acquisition_status",
    "index_status",
)


def upgrade() -> None:
    op.rename_table("rag_source_snapshot", "dinosaur_knowledge")
    op.execute(
        "ALTER TABLE dinosaur_knowledge "
        "RENAME CONSTRAINT uq_rag_source_snapshot_subject_source "
        "TO uq_dinosaur_knowledge_subject_source"
    )
    for column in _INDEXED_COLUMNS:
        op.execute(
            f"ALTER INDEX IF EXISTS ix_rag_source_snapshot_{column} "
            f"RENAME TO ix_dinosaur_knowledge_{column}"
        )


def downgrade() -> None:
    for column in _INDEXED_COLUMNS:
        op.execute(
            f"ALTER INDEX IF EXISTS ix_dinosaur_knowledge_{column} "
            f"RENAME TO ix_rag_source_snapshot_{column}"
        )
    op.execute(
        "ALTER TABLE dinosaur_knowledge "
        "RENAME CONSTRAINT uq_dinosaur_knowledge_subject_source "
        "TO uq_rag_source_snapshot_subject_source"
    )
    op.rename_table("dinosaur_knowledge", "rag_source_snapshot")
