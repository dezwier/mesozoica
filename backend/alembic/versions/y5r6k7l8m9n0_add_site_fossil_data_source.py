"""add site and fossil data_source

Revision ID: y5r6k7l8m9n0
Revises: x4q5k6l7m8n9
Create Date: 2026-07-17 19:30:00.000000

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "y5r6k7l8m9n0"
down_revision: Union[str, None] = "x4q5k6l7m8n9"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "site",
        sa.Column(
            "data_source",
            sa.String(length=16),
            nullable=False,
            server_default="archive",
        ),
    )
    op.create_index(op.f("ix_site_data_source"), "site", ["data_source"], unique=False)

    op.add_column(
        "fossil",
        sa.Column(
            "data_source",
            sa.String(length=16),
            nullable=False,
            server_default="archive",
        ),
    )
    op.create_index(
        op.f("ix_fossil_data_source"), "fossil", ["data_source"], unique=False
    )


def downgrade() -> None:
    op.drop_index(op.f("ix_fossil_data_source"), table_name="fossil")
    op.drop_column("fossil", "data_source")
    op.drop_index(op.f("ix_site_data_source"), table_name="site")
    op.drop_column("site", "data_source")
