"""add guidance_session table

Revision ID: m0n1o2p3q4r5
Revises: l9m0n1o2p3q4
Create Date: 2026-07-24 16:40:00.000000

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "m0n1o2p3q4r5"
down_revision: Union[str, None] = "l9m0n1o2p3q4"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "guidance_session",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("tool_id", sa.Integer(), nullable=False),
        sa.Column("action_key", sa.String(length=64), nullable=False),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("discovery_chance", sa.Float(), nullable=True),
        sa.Column("direction_exactness", sa.Float(), nullable=True),
        sa.Column("distance_exactness", sa.Float(), nullable=True),
        sa.Column("duration_minutes", sa.Integer(), nullable=False),
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
        op.f("ix_guidance_session_user_id"),
        "guidance_session",
        ["user_id"],
        unique=False,
    )
    op.create_index(
        op.f("ix_guidance_session_action_key"),
        "guidance_session",
        ["action_key"],
        unique=False,
    )
    op.create_index(
        op.f("ix_guidance_session_status"),
        "guidance_session",
        ["status"],
        unique=False,
    )
    op.create_index(
        op.f("ix_guidance_session_expires_at"),
        "guidance_session",
        ["expires_at"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index(op.f("ix_guidance_session_expires_at"), table_name="guidance_session")
    op.drop_index(op.f("ix_guidance_session_status"), table_name="guidance_session")
    op.drop_index(op.f("ix_guidance_session_action_key"), table_name="guidance_session")
    op.drop_index(op.f("ix_guidance_session_user_id"), table_name="guidance_session")
    op.drop_table("guidance_session")
