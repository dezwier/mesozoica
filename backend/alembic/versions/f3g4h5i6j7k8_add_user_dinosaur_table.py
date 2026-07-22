"""add user_dinosaur table

Revision ID: f3g4h5i6j7k8
Revises: e2f3a4b5c6d7
Create Date: 2026-07-22 10:00:00.000000

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "f3g4h5i6j7k8"
down_revision: Union[str, None] = "e2f3a4b5c6d7"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "user_dinosaur",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("dinosaur_id", sa.Integer(), nullable=False),
        sa.Column("role", sa.String(length=16), nullable=False),
        sa.Column(
            "timestamp",
            sa.DateTime(timezone=True),
            server_default=sa.text("CURRENT_TIMESTAMP"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(["dinosaur_id"], ["dinosaur.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["user_id"], ["user.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "user_id",
            "dinosaur_id",
            "role",
            name="uq_user_dinosaur_user_dinosaur_role",
        ),
    )
    op.create_index("ix_user_dinosaur_user_id", "user_dinosaur", ["user_id"])
    op.create_index("ix_user_dinosaur_dinosaur_id", "user_dinosaur", ["dinosaur_id"])
    op.create_index("ix_user_dinosaur_timestamp", "user_dinosaur", ["timestamp"])
    op.create_index(
        "ix_user_dinosaur_dinosaur_id_timestamp",
        "user_dinosaur",
        ["dinosaur_id", "timestamp"],
    )


def downgrade() -> None:
    op.drop_index(
        "ix_user_dinosaur_dinosaur_id_timestamp", table_name="user_dinosaur"
    )
    op.drop_index("ix_user_dinosaur_timestamp", table_name="user_dinosaur")
    op.drop_index("ix_user_dinosaur_dinosaur_id", table_name="user_dinosaur")
    op.drop_index("ix_user_dinosaur_user_id", table_name="user_dinosaur")
    op.drop_table("user_dinosaur")
