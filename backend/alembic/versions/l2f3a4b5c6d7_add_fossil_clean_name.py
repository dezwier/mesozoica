"""add fossil_clean name column

Revision ID: l2f3a4b5c6d7
Revises: k1e2f3a4b5c6
Create Date: 2026-07-12 18:45:00.000000

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "l2f3a4b5c6d7"
down_revision: Union[str, None] = "k1e2f3a4b5c6"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("fossil_clean", sa.Column("name", sa.String(length=255), nullable=True))


def downgrade() -> None:
    op.drop_column("fossil_clean", "name")
