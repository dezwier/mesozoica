"""replace explored distance with documentation progress

Revision ID: p5q6r7s8t9u0
Revises: o4p5q6r7s8t9
Create Date: 2026-08-06 12:00:00.000000

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "p5q6r7s8t9u0"
down_revision: Union[str, None] = "o4p5q6r7s8t9"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "user_site",
        sa.Column(
            "documentation_progress",
            sa.Float(),
            nullable=False,
            server_default="0",
        ),
    )
    op.execute(
        """
        UPDATE user_site
        SET documentation_progress = LEAST(
            1.0,
            GREATEST(0.0, explored_distance_m * 0.01)
        )
        """
    )
    op.drop_column("user_site", "explored_distance_m")


def downgrade() -> None:
    op.add_column(
        "user_site",
        sa.Column(
            "explored_distance_m",
            sa.Float(),
            nullable=False,
            server_default="0",
        ),
    )
    op.execute(
        """
        UPDATE user_site
        SET explored_distance_m = documentation_progress * 100.0
        """
    )
    op.drop_column("user_site", "documentation_progress")
