"""add dinosaur table

Revision ID: a1b2c3d4e5f6
Revises:
Create Date: 2026-07-11 08:00:00.000000

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "a1b2c3d4e5f6"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "dinosaur",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("name", sa.String(length=255), nullable=False),
        sa.Column("wikipedia_page_id", sa.Integer(), nullable=False),
        sa.Column("wikipedia_title", sa.String(length=255), nullable=False),
        sa.Column("birth", sa.Float(), nullable=True),
        sa.Column("death", sa.Float(), nullable=True),
        sa.Column("period", sa.String(length=255), nullable=True),
        sa.Column("cladogram", sa.JSON(), nullable=False),
        sa.Column("diet_type", sa.String(length=64), nullable=True),
        sa.Column("short_description", sa.Text(), nullable=True),
        sa.Column("long_description", sa.Text(), nullable=True),
        sa.Column("article", sa.Text(), nullable=True),
        sa.Column("article_date", sa.DateTime(), nullable=True),
        sa.Column("insert_date", sa.DateTime(), nullable=False),
        sa.Column("main_image_url", sa.String(length=2048), nullable=True),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_dinosaur_name"), "dinosaur", ["name"], unique=False)
    op.create_index(
        op.f("ix_dinosaur_wikipedia_page_id"),
        "dinosaur",
        ["wikipedia_page_id"],
        unique=True,
    )
    op.create_index(
        op.f("ix_dinosaur_wikipedia_title"),
        "dinosaur",
        ["wikipedia_title"],
        unique=True,
    )


def downgrade() -> None:
    op.drop_index(op.f("ix_dinosaur_wikipedia_title"), table_name="dinosaur")
    op.drop_index(op.f("ix_dinosaur_wikipedia_page_id"), table_name="dinosaur")
    op.drop_index(op.f("ix_dinosaur_name"), table_name="dinosaur")
    op.drop_table("dinosaur")
