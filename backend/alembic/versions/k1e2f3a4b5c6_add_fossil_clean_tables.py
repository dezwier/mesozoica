"""add fossil clean tables

Revision ID: k1e2f3a4b5c6
Revises: j0d1e2f3a4b5
Create Date: 2026-07-12 18:30:00.000000

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "k1e2f3a4b5c6"
down_revision: Union[str, None] = "j0d1e2f3a4b5"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "site_clean",
        sa.Column("site_id", sa.Integer(), nullable=False),
        sa.Column("latitude", sa.Numeric(precision=9, scale=6), nullable=True),
        sa.Column("longitude", sa.Numeric(precision=9, scale=6), nullable=True),
        sa.Column("country_code", sa.String(length=2), nullable=True),
        sa.Column("state", sa.String(length=100), nullable=True),
        sa.Column("rock_type", sa.String(length=100), nullable=True),
        sa.Column("formation", sa.String(length=255), nullable=True),
        sa.PrimaryKeyConstraint("site_id"),
    )
    op.create_table(
        "fossil_clean",
        sa.Column("fossil_id", sa.Integer(), nullable=False),
        sa.Column("site_id", sa.Integer(), nullable=False),
        sa.Column("dinosaur_id", sa.Integer(), nullable=False),
        sa.Column("type", sa.String(length=20), nullable=False),
        sa.Column("sub_category", sa.String(length=255), nullable=True),
        sa.Column("preservation_quality", sa.String(length=50), nullable=True),
        sa.Column("min_age_ma", sa.Numeric(precision=5, scale=2), nullable=True),
        sa.Column("max_age_ma", sa.Numeric(precision=5, scale=2), nullable=True),
        sa.Column("collection_year_min", sa.Integer(), nullable=True),
        sa.Column("collection_year_max", sa.Integer(), nullable=True),
        sa.ForeignKeyConstraint(["dinosaur_id"], ["dinosaur.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["fossil_id"], ["fossil.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["site_id"], ["site_clean.site_id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("fossil_id"),
    )
    op.create_index(op.f("ix_fossil_clean_dinosaur_id"), "fossil_clean", ["dinosaur_id"], unique=False)
    op.create_index(op.f("ix_fossil_clean_site_id"), "fossil_clean", ["site_id"], unique=False)


def downgrade() -> None:
    op.drop_index(op.f("ix_fossil_clean_site_id"), table_name="fossil_clean")
    op.drop_index(op.f("ix_fossil_clean_dinosaur_id"), table_name="fossil_clean")
    op.drop_table("fossil_clean")
    op.drop_table("site_clean")
