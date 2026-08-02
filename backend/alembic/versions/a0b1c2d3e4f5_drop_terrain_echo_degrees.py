"""drop unused terrain_echo_session.degrees column

Revision ID: a0b1c2d3e4f5
Revises: z9a0b1c2d3e4
Create Date: 2026-08-02 09:20:00.000000

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "a0b1c2d3e4f5"
down_revision: Union[str, None] = "z9a0b1c2d3e4"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if "terrain_echo_session" not in inspector.get_table_names():
        return
    cols = {c["name"] for c in inspector.get_columns("terrain_echo_session")}
    if "degrees" in cols:
        op.drop_column("terrain_echo_session", "degrees")


def downgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if "terrain_echo_session" not in inspector.get_table_names():
        return
    cols = {c["name"] for c in inspector.get_columns("terrain_echo_session")}
    if "degrees" not in cols:
        op.add_column(
            "terrain_echo_session",
            sa.Column("degrees", sa.Float(), nullable=False, server_default="20"),
        )
        op.alter_column("terrain_echo_session", "degrees", server_default=None)
