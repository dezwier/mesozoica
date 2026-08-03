"""add was_first on user_site

Revision ID: g6h7i8j9k0l1
Revises: f5a6b7c8d9e0
Create Date: 2026-08-03 22:20:00.000000

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "g6h7i8j9k0l1"
down_revision: Union[str, None] = "f5a6b7c8d9e0"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "user_site",
        sa.Column(
            "was_first",
            sa.Boolean(),
            nullable=False,
            server_default=sa.false(),
        ),
    )
    # Mark the earliest discoverer / documenter per site as was_first.
    bind = op.get_bind()
    if bind.dialect.name == "postgresql":
        op.execute(
            """
            UPDATE user_site AS us
            SET was_first = TRUE
            WHERE us.id IN (
                SELECT DISTINCT ON (site_id, role) id
                FROM user_site
                WHERE role IN ('discoverer', 'documenter')
                ORDER BY site_id, role, timestamp ASC, id ASC
            )
            """
        )
    else:
        op.execute(
            """
            UPDATE user_site
            SET was_first = 1
            WHERE id IN (
                SELECT us.id
                FROM user_site AS us
                WHERE us.role IN ('discoverer', 'documenter')
                  AND us.id = (
                    SELECT us2.id
                    FROM user_site AS us2
                    WHERE us2.site_id = us.site_id
                      AND us2.role = us.role
                    ORDER BY us2.timestamp ASC, us2.id ASC
                    LIMIT 1
                  )
            )
            """
        )


def downgrade() -> None:
    op.drop_column("user_site", "was_first")
