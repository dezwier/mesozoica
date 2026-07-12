"""add fossil occurrence detail fields

Revision ID: h8b9c0d1e2f3
Revises: g7a8b9c0d1e2
Create Date: 2026-07-12 09:50:00.000000

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "h8b9c0d1e2f3"
down_revision: Union[str, None] = "g7a8b9c0d1e2"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("fossil", sa.Column("collection_type", sa.String(length=50), nullable=True))
    op.add_column("fossil", sa.Column("occurrence_comments", sa.Text(), nullable=True))
    op.add_column("fossil", sa.Column("composition", sa.String(length=100), nullable=True))
    op.add_column("fossil", sa.Column("architecture", sa.String(length=100), nullable=True))
    op.add_column("fossil", sa.Column("fragmentation", sa.String(length=100), nullable=True))


def downgrade() -> None:
    op.drop_column("fossil", "fragmentation")
    op.drop_column("fossil", "architecture")
    op.drop_column("fossil", "composition")
    op.drop_column("fossil", "occurrence_comments")
    op.drop_column("fossil", "collection_type")
