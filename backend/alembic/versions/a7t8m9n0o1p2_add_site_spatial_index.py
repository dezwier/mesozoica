"""add site spatial index for field bbox queries

Revision ID: a7t8m9n0o1p2
Revises: z6s7l8m9n0o1
Create Date: 2026-07-19 10:00:00.000000

"""

from typing import Sequence, Union

from alembic import op

revision: str = "a7t8m9n0o1p2"
down_revision: Union[str, None] = "z6s7l8m9n0o1"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_index(
        "ix_site_data_source_lat_lon",
        "site",
        ["data_source", "latitude", "longitude"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index("ix_site_data_source_lat_lon", table_name="site")
