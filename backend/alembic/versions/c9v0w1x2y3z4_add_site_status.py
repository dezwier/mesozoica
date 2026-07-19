"""add site_status table and backfill field sites as hidden

Revision ID: c9v0w1x2y3z4
Revises: b8u9v0w1x2y3
Create Date: 2026-07-19 10:55:00.000000

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "c9v0w1x2y3z4"
down_revision: Union[str, None] = "b8u9v0w1x2y3"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "site_status",
        sa.Column("site_id", sa.Integer(), nullable=False),
        sa.Column(
            "timestamp",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.ForeignKeyConstraint(
            ["site_id"],
            ["site.site_id"],
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("site_id"),
    )
    op.execute(
        sa.text(
            """
            INSERT INTO site_status (site_id, timestamp, status)
            SELECT site_id, NOW(), 'hidden'
            FROM site
            WHERE data_source = 'field'
            """
        )
    )


def downgrade() -> None:
    op.drop_table("site_status")
