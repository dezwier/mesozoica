"""add terrain_echo_session for vintage radar overlay

Revision ID: z9a0b1c2d3e4
Revises: y8z9a0b1c2d3
Create Date: 2026-08-02 08:20:00.000000

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "z9a0b1c2d3e4"
down_revision: Union[str, None] = "y8z9a0b1c2d3"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "terrain_echo_session",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("tool_id", sa.Integer(), nullable=False),
        sa.Column("action_key", sa.String(length=64), nullable=False),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("duration_minutes", sa.Integer(), nullable=False),
        sa.Column("degrees", sa.Float(), nullable=False),
        sa.Column("accuracy", sa.Float(), nullable=False),
        sa.Column("range_m", sa.Float(), nullable=False),
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
        op.f("ix_terrain_echo_session_user_id"),
        "terrain_echo_session",
        ["user_id"],
        unique=False,
    )
    op.create_index(
        op.f("ix_terrain_echo_session_action_key"),
        "terrain_echo_session",
        ["action_key"],
        unique=False,
    )
    op.create_index(
        op.f("ix_terrain_echo_session_status"),
        "terrain_echo_session",
        ["status"],
        unique=False,
    )
    op.create_index(
        op.f("ix_terrain_echo_session_expires_at"),
        "terrain_echo_session",
        ["expires_at"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index(
        op.f("ix_terrain_echo_session_expires_at"),
        table_name="terrain_echo_session",
    )
    op.drop_index(
        op.f("ix_terrain_echo_session_status"),
        table_name="terrain_echo_session",
    )
    op.drop_index(
        op.f("ix_terrain_echo_session_action_key"),
        table_name="terrain_echo_session",
    )
    op.drop_index(
        op.f("ix_terrain_echo_session_user_id"),
        table_name="terrain_echo_session",
    )
    op.drop_table("terrain_echo_session")
