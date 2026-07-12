"""add fossil_clean comment column

Revision ID: m3f4a5b6c7d8
Revises: l2f3a4b5c6d7
Create Date: 2026-07-12 18:50:00.000000

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "m3f4a5b6c7d8"
down_revision: Union[str, None] = "l2f3a4b5c6d7"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("fossil_clean", sa.Column("comment", sa.Text(), nullable=True))


def downgrade() -> None:
    op.drop_column("fossil_clean", "comment")
