"""add fossil.depth_cm for field burial depth

Revision ID: g4h5i6j7k8l9
Revises: f3g4h5i6j7k8
Create Date: 2026-07-22 15:50:00.000000

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "g4h5i6j7k8l9"
down_revision: Union[str, None] = "f3g4h5i6j7k8"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "fossil",
        sa.Column("depth_cm", sa.Integer(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("fossil", "depth_cm")
