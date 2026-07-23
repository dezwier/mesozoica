"""add user_tool table

Revision ID: i6j7k8l9m0n1
Revises: h5i6j7k8l9m0
Create Date: 2026-07-23 07:30:00.000000

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "i6j7k8l9m0n1"
down_revision: Union[str, None] = "h5i6j7k8l9m0"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "user_tool",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("tool_id", sa.Integer(), nullable=False),
        sa.Column("level", sa.Integer(), nullable=False, server_default="1"),
        sa.Column(
            "timestamp",
            sa.DateTime(timezone=True),
            server_default=sa.text("CURRENT_TIMESTAMP"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(["tool_id"], ["tool.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["user_id"], ["user.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "user_id",
            "tool_id",
            name="uq_user_tool_user_tool",
        ),
    )
    op.create_index("ix_user_tool_user_id", "user_tool", ["user_id"])
    op.create_index("ix_user_tool_tool_id", "user_tool", ["tool_id"])
    op.create_index("ix_user_tool_timestamp", "user_tool", ["timestamp"])


def downgrade() -> None:
    op.drop_index("ix_user_tool_timestamp", table_name="user_tool")
    op.drop_index("ix_user_tool_tool_id", table_name="user_tool")
    op.drop_index("ix_user_tool_user_id", table_name="user_tool")
    op.drop_table("user_tool")
