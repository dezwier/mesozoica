"""add reason to field_ensure_job

Revision ID: b8u9v0w1x2y3
Revises: a7t8m9n0o1p2
Create Date: 2026-07-18 16:45:00.000000

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "b8u9v0w1x2y3"
down_revision: Union[str, None] = "a7t8m9n0o1p2"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "field_ensure_job",
        sa.Column("reason", sa.String(length=32), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("field_ensure_job", "reason")
