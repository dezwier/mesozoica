"""add site_type.main_image_url

Revision ID: p6i7d8e9f0g1
Revises: o5h6c7d8e9f0
Create Date: 2026-07-12 19:10:00.000000

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "p6i7d8e9f0g1"
down_revision: Union[str, None] = "o5h6c7d8e9f0"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "site_type",
        sa.Column("main_image_url", sa.String(length=512), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("site_type", "main_image_url")
