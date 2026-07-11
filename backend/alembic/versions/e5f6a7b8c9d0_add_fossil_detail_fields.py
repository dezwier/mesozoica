"""add fossil detail fields

Revision ID: e5f6a7b8c9d0
Revises: d4e5f6a7b8c9
Create Date: 2026-07-11 20:50:00.000000

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "e5f6a7b8c9d0"
down_revision: Union[str, None] = "d4e5f6a7b8c9"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("fossil", sa.Column("early_interval", sa.String(length=100), nullable=True))
    op.add_column("fossil", sa.Column("family", sa.String(length=100), nullable=True))
    op.add_column("fossil", sa.Column("collection_name", sa.String(length=255), nullable=True))
    op.add_column("fossil", sa.Column("collection_dates", sa.String(length=100), nullable=True))
    op.add_column("fossil", sa.Column("stratcomments", sa.Text(), nullable=True))
    op.add_column("fossil", sa.Column("lithdescript", sa.String(length=500), nullable=True))
    op.add_column("fossil", sa.Column("collectors", sa.String(length=500), nullable=True))
    op.add_column("fossil", sa.Column("museum", sa.String(length=100), nullable=True))
    op.add_column("fossil", sa.Column("pres_mode", sa.String(length=50), nullable=True))
    op.add_column(
        "fossil", sa.Column("preservation_quality", sa.String(length=50), nullable=True)
    )
    op.add_column("fossil", sa.Column("abund_value", sa.Integer(), nullable=True))
    op.add_column("fossil", sa.Column("abund_unit", sa.String(length=50), nullable=True))


def downgrade() -> None:
    op.drop_column("fossil", "abund_unit")
    op.drop_column("fossil", "abund_value")
    op.drop_column("fossil", "preservation_quality")
    op.drop_column("fossil", "pres_mode")
    op.drop_column("fossil", "museum")
    op.drop_column("fossil", "collectors")
    op.drop_column("fossil", "lithdescript")
    op.drop_column("fossil", "stratcomments")
    op.drop_column("fossil", "collection_dates")
    op.drop_column("fossil", "collection_name")
    op.drop_column("fossil", "family")
    op.drop_column("fossil", "early_interval")
