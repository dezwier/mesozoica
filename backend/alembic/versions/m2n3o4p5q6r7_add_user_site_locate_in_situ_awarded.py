"""add locate_in_situ_awarded on user_site

Revision ID: m2n3o4p5q6r7
Revises: l1m2n3o4p5q6
Create Date: 2026-08-05 09:20:00.000000

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "m2n3o4p5q6r7"
down_revision: Union[str, None] = "l1m2n3o4p5q6"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "user_site",
        sa.Column(
            "locate_in_situ_awarded",
            sa.Boolean(),
            nullable=False,
            server_default=sa.false(),
        ),
    )
    # Prior surface grants created user_fossil in_situ rows; treat those as awarded.
    op.execute(
        """
        UPDATE user_site AS us
        SET locate_in_situ_awarded = TRUE
        WHERE us.role = 'discoverer'
          AND EXISTS (
            SELECT 1
            FROM user_fossil AS uf
            JOIN fossil AS f ON f.id = uf.fossil_id
            WHERE uf.user_id = us.user_id
              AND f.site_id = us.site_id
              AND uf.role = 'in_situ'
          )
        """
    )


def downgrade() -> None:
    op.drop_column("user_site", "locate_in_situ_awarded")
