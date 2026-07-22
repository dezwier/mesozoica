"""add site odd_* scores for field fossil generation

Revision ID: h5i6j7k8l9m0
Revises: g4h5i6j7k8l9
Create Date: 2026-07-22 23:10:00.000000

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "h5i6j7k8l9m0"
down_revision: Union[str, None] = "g4h5i6j7k8l9"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("site", sa.Column("odd_dino_count", sa.Float(), nullable=True))
    op.add_column("site", sa.Column("odd_fossil_count", sa.Float(), nullable=True))
    op.add_column("site", sa.Column("odd_completeness", sa.Float(), nullable=True))
    op.add_column("site", sa.Column("odd_quality", sa.Float(), nullable=True))
    op.add_column("site", sa.Column("odd_depth", sa.Float(), nullable=True))
    op.execute(
        sa.text(
            """
            UPDATE site
            SET
                odd_dino_count = random(),
                odd_fossil_count = random(),
                odd_completeness = random(),
                odd_quality = random(),
                odd_depth = random()
            WHERE data_source = 'field'
            """
        )
    )


def downgrade() -> None:
    op.drop_column("site", "odd_depth")
    op.drop_column("site", "odd_quality")
    op.drop_column("site", "odd_completeness")
    op.drop_column("site", "odd_fossil_count")
    op.drop_column("site", "odd_dino_count")
