"""add site period

Revision ID: z6s7l8m9n0o1
Revises: y5r6k7l8m9n0
Create Date: 2026-07-18 07:35:00.000000

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "z6s7l8m9n0o1"
down_revision: Union[str, None] = "y5r6k7l8m9n0"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "site",
        sa.Column("period", sa.String(length=20), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("site", "period")
