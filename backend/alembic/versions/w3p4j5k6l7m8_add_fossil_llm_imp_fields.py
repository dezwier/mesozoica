"""add fossil llm imputed enrichment fields

Revision ID: w3p4j5k6l7m8
Revises: v2o3i4j5k6l7
Create Date: 2026-07-16 08:00:00.000000

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "w3p4j5k6l7m8"
down_revision: Union[str, None] = "v2o3i4j5k6l7"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("fossil", sa.Column("llm_imp_rock_type", sa.String(length=64), nullable=True))
    op.add_column("fossil", sa.Column("llm_imp_category", sa.String(length=32), nullable=True))
    op.add_column("fossil", sa.Column("llm_imp_subcategory", sa.String(length=64), nullable=True))
    op.add_column(
        "fossil",
        sa.Column("llm_imp_preservation_quality", sa.String(length=32), nullable=True),
    )
    op.add_column("fossil", sa.Column("llm_imp_completeness", sa.String(length=32), nullable=True))


def downgrade() -> None:
    op.drop_column("fossil", "llm_imp_completeness")
    op.drop_column("fossil", "llm_imp_preservation_quality")
    op.drop_column("fossil", "llm_imp_subcategory")
    op.drop_column("fossil", "llm_imp_category")
    op.drop_column("fossil", "llm_imp_rock_type")
