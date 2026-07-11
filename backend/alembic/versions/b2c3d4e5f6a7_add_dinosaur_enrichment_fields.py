"""add dinosaur enrichment fields

Revision ID: b2c3d4e5f6a7
Revises: a1b2c3d4e5f6
Create Date: 2026-07-11 10:20:00.000000

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "b2c3d4e5f6a7"
down_revision: Union[str, None] = "a1b2c3d4e5f6"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("dinosaur", sa.Column("length", sa.String(length=128), nullable=True))
    op.add_column("dinosaur", sa.Column("mass", sa.String(length=128), nullable=True))
    op.add_column("dinosaur", sa.Column("location", sa.String(length=512), nullable=True))
    op.add_column(
        "dinosaur",
        sa.Column("llm_enriched", sa.Boolean(), nullable=False, server_default=sa.false()),
    )
    op.create_index(op.f("ix_dinosaur_llm_enriched"), "dinosaur", ["llm_enriched"], unique=False)


def downgrade() -> None:
    op.drop_index(op.f("ix_dinosaur_llm_enriched"), table_name="dinosaur")
    op.drop_column("dinosaur", "llm_enriched")
    op.drop_column("dinosaur", "location")
    op.drop_column("dinosaur", "mass")
    op.drop_column("dinosaur", "length")
