"""add fossil pbdb comps fields

Revision ID: j0d1e2f3a4b5
Revises: i9c0d1e2f3a4
Create Date: 2026-07-12 15:05:00.000000

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "j0d1e2f3a4b5"
down_revision: Union[str, None] = "i9c0d1e2f3a4"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("fossil", sa.Column("articulated_parts", sa.String(length=100), nullable=True))
    op.add_column("fossil", sa.Column("associated_parts", sa.String(length=255), nullable=True))
    op.add_column("fossil", sa.Column("common_body_parts", sa.String(length=255), nullable=True))
    op.add_column("fossil", sa.Column("rare_body_parts", sa.String(length=255), nullable=True))
    op.add_column("fossil", sa.Column("feed_pred_traces", sa.String(length=255), nullable=True))
    op.add_column("fossil", sa.Column("artifacts", sa.String(length=255), nullable=True))
    op.add_column("fossil", sa.Column("component_comments", sa.Text(), nullable=True))


def downgrade() -> None:
    op.drop_column("fossil", "component_comments")
    op.drop_column("fossil", "artifacts")
    op.drop_column("fossil", "feed_pred_traces")
    op.drop_column("fossil", "rare_body_parts")
    op.drop_column("fossil", "common_body_parts")
    op.drop_column("fossil", "associated_parts")
    op.drop_column("fossil", "articulated_parts")
