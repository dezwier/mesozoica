"""user_site source_mission_id; tool_mission flight param snapshots

Revision ID: l9m0n1o2p3q4
Revises: k8l9m0n1o2p3
Create Date: 2026-07-24 08:00:00.000000

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "l9m0n1o2p3q4"
down_revision: Union[str, None] = "k8l9m0n1o2p3"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "user_site",
        sa.Column("source_mission_id", sa.Integer(), nullable=True),
    )
    op.create_foreign_key(
        "fk_user_site_source_mission_id",
        "user_site",
        "tool_mission",
        ["source_mission_id"],
        ["id"],
        ondelete="SET NULL",
    )
    op.create_index(
        op.f("ix_user_site_source_mission_id"),
        "user_site",
        ["source_mission_id"],
        unique=False,
    )

    op.add_column(
        "tool_mission",
        sa.Column("flight_speed_kmh", sa.Float(), nullable=True),
    )
    op.add_column(
        "tool_mission",
        sa.Column("max_route_km", sa.Float(), nullable=True),
    )
    op.add_column(
        "tool_mission",
        sa.Column("discovery_chance", sa.Float(), nullable=True),
    )
    op.add_column(
        "tool_mission",
        sa.Column("discovery_distance_m", sa.Float(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("tool_mission", "discovery_distance_m")
    op.drop_column("tool_mission", "discovery_chance")
    op.drop_column("tool_mission", "max_route_km")
    op.drop_column("tool_mission", "flight_speed_kmh")

    op.drop_index(op.f("ix_user_site_source_mission_id"), table_name="user_site")
    op.drop_constraint(
        "fk_user_site_source_mission_id", "user_site", type_="foreignkey"
    )
    op.drop_column("user_site", "source_mission_id")
