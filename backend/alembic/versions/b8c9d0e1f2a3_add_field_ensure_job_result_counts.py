"""add field ensure job result counts

Revision ID: b8c9d0e1f2a3
Revises: a7t8u9v0w1x2
Create Date: 2026-07-19 17:15:00.000000

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "b8c9d0e1f2a3"
down_revision: Union[str, None] = "a7t8u9v0w1x2"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "field_ensure_job",
        sa.Column("generated_count", sa.Integer(), nullable=True),
    )
    op.add_column(
        "field_ensure_job",
        sa.Column("total_in_radius", sa.Integer(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("field_ensure_job", "total_in_radius")
    op.drop_column("field_ensure_job", "generated_count")
