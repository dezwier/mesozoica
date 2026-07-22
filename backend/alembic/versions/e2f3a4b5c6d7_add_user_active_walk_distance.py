"""add user active walk distance fields

Revision ID: e2f3a4b5c6d7
Revises: d1e2f3a4b5c6
Create Date: 2026-07-22 09:30:00.000000

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "e2f3a4b5c6d7"
down_revision: Union[str, None] = "d1e2f3a4b5c6"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "user",
        sa.Column(
            "active_distance_m",
            sa.Float(),
            nullable=False,
            server_default="0",
        ),
    )
    op.add_column(
        "user",
        sa.Column(
            "active_weekly_distance_m",
            sa.Float(),
            nullable=False,
            server_default="0",
        ),
    )


def downgrade() -> None:
    op.drop_column("user", "active_weekly_distance_m")
    op.drop_column("user", "active_distance_m")
