"""Migrate user_fossil/user_dinosaur roles to new status vocabularies.

Revision ID: v5w6x7y8z9a0
Revises: u4v5w6x7y8z9
Create Date: 2026-07-30 22:55:00.000000

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "v5w6x7y8z9a0"
down_revision: Union[str, None] = "u4v5w6x7y8z9"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    conn = op.get_bind()
    conn.execute(
        sa.text(
            "UPDATE user_fossil SET role = 'in_situ' WHERE role = 'discoverer'"
        )
    )
    conn.execute(
        sa.text(
            "UPDATE user_dinosaur SET role = 'modelled' WHERE role = 'discoverer'"
        )
    )


def downgrade() -> None:
    conn = op.get_bind()
    conn.execute(
        sa.text(
            "UPDATE user_fossil SET role = 'discoverer' WHERE role = 'in_situ'"
        )
    )
    conn.execute(
        sa.text(
            "UPDATE user_dinosaur SET role = 'discoverer' WHERE role = 'modelled'"
        )
    )
