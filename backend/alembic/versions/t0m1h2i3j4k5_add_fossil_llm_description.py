"""add fossil llm_description field

Revision ID: t0m1h2i3j4k5
Revises: s9l0g1h2i3j4
Create Date: 2026-07-14 12:30:00.000000

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "t0m1h2i3j4k5"
down_revision: Union[str, None] = "s9l0g1h2i3j4"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("fossil", sa.Column("llm_description", sa.Text(), nullable=True))


def downgrade() -> None:
    op.drop_column("fossil", "llm_description")
