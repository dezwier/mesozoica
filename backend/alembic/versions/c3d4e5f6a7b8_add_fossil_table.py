"""add fossil table

Revision ID: c3d4e5f6a7b8
Revises: b2c3d4e5f6a7
Create Date: 2026-07-11 15:55:00.000000

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "c3d4e5f6a7b8"
down_revision: Union[str, None] = "b2c3d4e5f6a7"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "fossil",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("dinosaur_id", sa.Integer(), nullable=False),
        sa.Column("identified_name", sa.String(length=255), nullable=True),
        sa.Column("latitude", sa.Numeric(precision=9, scale=6), nullable=True),
        sa.Column("longitude", sa.Numeric(precision=9, scale=6), nullable=True),
        sa.Column("country_code", sa.String(length=2), nullable=True),
        sa.Column("state", sa.String(length=100), nullable=True),
        sa.Column("geological_formation", sa.String(length=255), nullable=True),
        sa.Column("min_age_ma", sa.Numeric(precision=5, scale=2), nullable=True),
        sa.Column("max_age_ma", sa.Numeric(precision=5, scale=2), nullable=True),
        sa.ForeignKeyConstraint(["dinosaur_id"], ["dinosaur.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_fossil_dinosaur_id"), "fossil", ["dinosaur_id"], unique=False)


def downgrade() -> None:
    op.drop_index(op.f("ix_fossil_dinosaur_id"), table_name="fossil")
    op.drop_table("fossil")
