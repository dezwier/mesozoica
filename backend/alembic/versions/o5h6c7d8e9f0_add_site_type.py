"""add site_type table and site_clean.site_type_id

Revision ID: o5h6c7d8e9f0
Revises: n4g5b6c7d8e9
Create Date: 2026-07-12 19:00:00.000000

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "o5h6c7d8e9f0"
down_revision: Union[str, None] = "n4g5b6c7d8e9"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "site_type",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("period", sa.String(length=20), nullable=False),
        sa.Column("rock_type", sa.String(length=100), nullable=False),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("period", "rock_type", name="uq_site_type_period_rock_type"),
    )
    op.add_column("site_clean", sa.Column("site_type_id", sa.Integer(), nullable=True))
    op.create_index(op.f("ix_site_clean_site_type_id"), "site_clean", ["site_type_id"], unique=False)
    op.create_foreign_key(
        "fk_site_clean_site_type_id",
        "site_clean",
        "site_type",
        ["site_type_id"],
        ["id"],
        ondelete="SET NULL",
    )


def downgrade() -> None:
    op.drop_constraint("fk_site_clean_site_type_id", "site_clean", type_="foreignkey")
    op.drop_index(op.f("ix_site_clean_site_type_id"), table_name="site_clean")
    op.drop_column("site_clean", "site_type_id")
    op.drop_table("site_type")
