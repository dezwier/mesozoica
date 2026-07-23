"""tool action column and tool mission tables

Revision ID: j7k8l9m0n1o2
Revises: i6j7k8l9m0n1
Create Date: 2026-07-23 08:00:00.000000

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "j7k8l9m0n1o2"
down_revision: Union[str, None] = "i6j7k8l9m0n1"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "tool",
        sa.Column(
            "action",
            sa.String(length=40),
            nullable=False,
            server_default="Use",
        ),
    )

    op.create_table(
        "tool_mission",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("tool_id", sa.Integer(), nullable=False),
        sa.Column("action_key", sa.String(length=64), nullable=False),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("route_json", sa.Text(), nullable=False),
        sa.Column("route_length_km", sa.Float(), nullable=False),
        sa.Column("flight_duration_s", sa.Integer(), nullable=False),
        sa.Column("ensure_job_ids_json", sa.Text(), nullable=True),
        sa.Column("flight_started_at", sa.DateTime(), nullable=True),
        sa.Column("flight_ends_at", sa.DateTime(), nullable=True),
        sa.Column("error_message", sa.String(length=2000), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["tool_id"], ["tool.id"]),
        sa.ForeignKeyConstraint(["user_id"], ["user.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        op.f("ix_tool_mission_user_id"), "tool_mission", ["user_id"], unique=False
    )
    op.create_index(
        op.f("ix_tool_mission_status"), "tool_mission", ["status"], unique=False
    )
    op.create_index(
        op.f("ix_tool_mission_action_key"),
        "tool_mission",
        ["action_key"],
        unique=False,
    )

    op.create_table(
        "tool_mission_event",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("mission_id", sa.Integer(), nullable=False),
        sa.Column("event_type", sa.String(length=32), nullable=False),
        sa.Column("site_id", sa.Integer(), nullable=True),
        sa.Column("due_at", sa.DateTime(), nullable=False),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("lat", sa.Float(), nullable=True),
        sa.Column("lon", sa.Float(), nullable=True),
        sa.Column("distance_along_km", sa.Float(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("processed_at", sa.DateTime(), nullable=True),
        sa.ForeignKeyConstraint(["mission_id"], ["tool_mission.id"]),
        sa.ForeignKeyConstraint(["site_id"], ["site.site_id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        op.f("ix_tool_mission_event_mission_id"),
        "tool_mission_event",
        ["mission_id"],
        unique=False,
    )
    op.create_index(
        op.f("ix_tool_mission_event_status"),
        "tool_mission_event",
        ["status"],
        unique=False,
    )
    op.create_index(
        op.f("ix_tool_mission_event_due_at"),
        "tool_mission_event",
        ["due_at"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index(
        op.f("ix_tool_mission_event_due_at"), table_name="tool_mission_event"
    )
    op.drop_index(
        op.f("ix_tool_mission_event_status"), table_name="tool_mission_event"
    )
    op.drop_index(
        op.f("ix_tool_mission_event_mission_id"), table_name="tool_mission_event"
    )
    op.drop_table("tool_mission_event")
    op.drop_index(op.f("ix_tool_mission_action_key"), table_name="tool_mission")
    op.drop_index(op.f("ix_tool_mission_status"), table_name="tool_mission")
    op.drop_index(op.f("ix_tool_mission_user_id"), table_name="tool_mission")
    op.drop_table("tool_mission")
    op.drop_column("tool", "action")
