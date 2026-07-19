"""add device tokens and site_discovered notification site_id

Revision ID: f2y3z4a5b6c7
Revises: e1x2y3z4a5b6
Create Date: 2026-07-19 13:30:00.000000

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "f2y3z4a5b6c7"
down_revision: Union[str, None] = "e1x2y3z4a5b6"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "user_device_token",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("token", sa.String(length=512), nullable=False),
        sa.Column("platform", sa.String(length=16), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("last_used_at", sa.DateTime(), nullable=True),
        sa.ForeignKeyConstraint(["user_id"], ["user.id"]),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("token"),
    )
    op.create_index(
        op.f("ix_user_device_token_token"),
        "user_device_token",
        ["token"],
        unique=False,
    )
    op.create_index(
        op.f("ix_user_device_token_user_id"),
        "user_device_token",
        ["user_id"],
        unique=False,
    )
    op.add_column(
        "user_notification",
        sa.Column("site_id", sa.Integer(), nullable=True),
    )
    op.create_foreign_key(
        "fk_user_notification_site_id",
        "user_notification",
        "site",
        ["site_id"],
        ["site_id"],
        ondelete="SET NULL",
    )
    op.create_index(
        op.f("ix_user_notification_site_id"),
        "user_notification",
        ["site_id"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index(op.f("ix_user_notification_site_id"), table_name="user_notification")
    op.drop_constraint(
        "fk_user_notification_site_id",
        "user_notification",
        type_="foreignkey",
    )
    op.drop_column("user_notification", "site_id")
    op.drop_index(op.f("ix_user_device_token_user_id"), table_name="user_device_token")
    op.drop_index(op.f("ix_user_device_token_token"), table_name="user_device_token")
    op.drop_table("user_device_token")
