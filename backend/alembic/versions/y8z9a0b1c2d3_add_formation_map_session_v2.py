"""add formation_map_session for rock-type square mosaic

Revision ID: y8z9a0b1c2d3
Revises: x7y8z9a0b1c2
Create Date: 2026-08-01 19:50:00.000000

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "y8z9a0b1c2d3"
down_revision: Union[str, None] = "x7y8z9a0b1c2"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "formation_map_session",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("tool_id", sa.Integer(), nullable=False),
        sa.Column("action_key", sa.String(length=64), nullable=False),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("duration_minutes", sa.Integer(), nullable=False),
        sa.Column("accuracy", sa.Float(), nullable=False),
        sa.Column("wideness_m", sa.Float(), nullable=False),
        sa.Column("cell_size_m", sa.Float(), nullable=False),
        sa.Column("center_lat", sa.Float(), nullable=False),
        sa.Column("center_lon", sa.Float(), nullable=False),
        sa.Column("started_at", sa.DateTime(), nullable=False),
        sa.Column("expires_at", sa.DateTime(), nullable=False),
        sa.Column("cancelled_at", sa.DateTime(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["tool_id"], ["tool.id"]),
        sa.ForeignKeyConstraint(["user_id"], ["user.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        op.f("ix_formation_map_session_user_id"),
        "formation_map_session",
        ["user_id"],
        unique=False,
    )
    op.create_index(
        op.f("ix_formation_map_session_action_key"),
        "formation_map_session",
        ["action_key"],
        unique=False,
    )
    op.create_index(
        op.f("ix_formation_map_session_status"),
        "formation_map_session",
        ["status"],
        unique=False,
    )
    op.create_index(
        op.f("ix_formation_map_session_expires_at"),
        "formation_map_session",
        ["expires_at"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index(
        op.f("ix_formation_map_session_expires_at"),
        table_name="formation_map_session",
    )
    op.drop_index(
        op.f("ix_formation_map_session_status"),
        table_name="formation_map_session",
    )
    op.drop_index(
        op.f("ix_formation_map_session_action_key"),
        table_name="formation_map_session",
    )
    op.drop_index(
        op.f("ix_formation_map_session_user_id"),
        table_name="formation_map_session",
    )
    op.drop_table("formation_map_session")
