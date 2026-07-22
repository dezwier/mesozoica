"""add user walk distance fields

Revision ID: a7t8u9v0w1x2
Revises: z6s7l8m9n0o1
Create Date: 2026-07-22 09:00:00.000000

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "a7t8u9v0w1x2"
down_revision: Union[str, None] = "z6s7l8m9n0o1"
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
