"""add version string to dinosaur, tool, fossil, site occurrence tables

Revision ID: u4v5w6x7y8z9
Revises: t3u4v5w6x7y8
Create Date: 2026-07-30 17:30:00.000000

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "u4v5w6x7y8z9"
down_revision: Union[str, None] = "t3u4v5w6x7y8"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_ORIGINAL = "Original"


def upgrade() -> None:
    for table in ("dinosaur", "tool", "fossil", "site"):
        op.add_column(
            table,
            sa.Column(
                "version",
                sa.String(length=64),
                nullable=False,
                server_default=_ORIGINAL,
            ),
        )
        op.execute(
            sa.text(f'UPDATE "{table}" SET version = :v').bindparams(v=_ORIGINAL)
        )


def downgrade() -> None:
    for table in ("site", "fossil", "tool", "dinosaur"):
        op.drop_column(table, "version")
