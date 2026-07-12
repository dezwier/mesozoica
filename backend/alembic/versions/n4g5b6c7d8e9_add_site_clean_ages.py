"""add site_clean age columns

Revision ID: n4g5b6c7d8e9
Revises: m3f4a5b6c7d8
Create Date: 2026-07-12 18:55:00.000000

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "n4g5b6c7d8e9"
down_revision: Union[str, None] = "m3f4a5b6c7d8"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("site_clean", sa.Column("min_age_ma", sa.Numeric(precision=5, scale=2), nullable=True))
    op.add_column("site_clean", sa.Column("max_age_ma", sa.Numeric(precision=5, scale=2), nullable=True))


def downgrade() -> None:
    op.drop_column("site_clean", "max_age_ma")
    op.drop_column("site_clean", "min_age_ma")
