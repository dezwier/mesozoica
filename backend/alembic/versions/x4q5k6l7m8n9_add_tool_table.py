"""add tool table

Revision ID: x4q5k6l7m8n9
Revises: w3p4j5k6l7m8
Create Date: 2026-07-17 12:00:00.000000

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "x4q5k6l7m8n9"
down_revision: Union[str, None] = "w3p4j5k6l7m8"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "tool",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("name", sa.String(length=100), nullable=False),
        sa.Column("category", sa.String(length=50), nullable=False),
        sa.Column("scientific_tool", sa.String(length=100), nullable=False),
        sa.Column("description", sa.String(length=500), nullable=False),
        sa.Column("rarity", sa.Integer(), nullable=False),
        sa.Column("main_image_url", sa.String(length=512), nullable=True),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("name"),
    )
    op.create_index(op.f("ix_tool_name"), "tool", ["name"], unique=True)


def downgrade() -> None:
    op.drop_index(op.f("ix_tool_name"), table_name="tool")
    op.drop_table("tool")
