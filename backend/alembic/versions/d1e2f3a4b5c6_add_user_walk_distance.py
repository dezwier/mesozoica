"""add user walk distance fields

Revision ID: d1e2f3a4b5c6
Revises: c9d0e1f2a3b4
Create Date: 2026-07-22 09:15:00.000000

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "d1e2f3a4b5c6"
down_revision: Union[str, None] = "c9d0e1f2a3b4"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "user",
        sa.Column(
            "total_distance_m",
            sa.Float(),
            nullable=False,
            server_default="0",
        ),
    )
    op.add_column(
        "user",
        sa.Column(
            "weekly_distance_m",
            sa.Float(),
            nullable=False,
            server_default="0",
        ),
    )
    op.add_column(
        "user",
        sa.Column("distance_week_start", sa.Date(), nullable=True),
    )
    op.add_column(
        "user",
        sa.Column("distance_synced_at", sa.DateTime(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("user", "distance_synced_at")
    op.drop_column("user", "distance_week_start")
    op.drop_column("user", "weekly_distance_m")
    op.drop_column("user", "total_distance_m")
