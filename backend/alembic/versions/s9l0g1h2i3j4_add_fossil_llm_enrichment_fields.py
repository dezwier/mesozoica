"""add fossil llm enrichment fields

Revision ID: s9l0g1h2i3j4
Revises: r8k9f0g1h2i3
Create Date: 2026-07-14 12:00:00.000000

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "s9l0g1h2i3j4"
down_revision: Union[str, None] = "r8k9f0g1h2i3"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("fossil", sa.Column("llm_rock_type", sa.String(length=64), nullable=True))
    op.add_column("fossil", sa.Column("llm_category", sa.String(length=32), nullable=True))
    op.add_column("fossil", sa.Column("llm_subcategory", sa.String(length=64), nullable=True))
    op.add_column(
        "fossil",
        sa.Column("llm_preservation_quality", sa.String(length=32), nullable=True),
    )
    op.add_column("fossil", sa.Column("llm_completeness", sa.String(length=32), nullable=True))
    op.add_column(
        "fossil",
        sa.Column("llm_enriched", sa.Boolean(), nullable=False, server_default=sa.false()),
    )
    op.create_index(op.f("ix_fossil_llm_enriched"), "fossil", ["llm_enriched"], unique=False)


def downgrade() -> None:
    op.drop_index(op.f("ix_fossil_llm_enriched"), table_name="fossil")
    op.drop_column("fossil", "llm_enriched")
    op.drop_column("fossil", "llm_completeness")
    op.drop_column("fossil", "llm_preservation_quality")
    op.drop_column("fossil", "llm_subcategory")
    op.drop_column("fossil", "llm_category")
    op.drop_column("fossil", "llm_rock_type")
