"""create user_site and drop site_status

Revision ID: e1x2y3z4a5b6
Revises: d0w1x2y3z4a5
Create Date: 2026-07-19 12:00:00.000000

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "e1x2y3z4a5b6"
down_revision: Union[str, None] = "d0w1x2y3z4a5"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "user_site",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("site_id", sa.Integer(), nullable=False),
        sa.Column("role", sa.String(length=16), nullable=False),
        sa.Column(
            "timestamp",
            sa.DateTime(timezone=True),
            server_default=sa.text("CURRENT_TIMESTAMP"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(["site_id"], ["site.site_id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["user_id"], ["user.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "user_id",
            "site_id",
            "role",
            name="uq_user_site_user_site_role",
        ),
    )
    op.create_index("ix_user_site_user_id", "user_site", ["user_id"])
    op.create_index("ix_user_site_site_id", "user_site", ["site_id"])
    op.create_index("ix_user_site_timestamp", "user_site", ["timestamp"])
    op.create_index(
        "ix_user_site_site_id_timestamp",
        "user_site",
        ["site_id", "timestamp"],
    )
    op.create_index(
        "uq_user_site_one_excavator",
        "user_site",
        ["site_id"],
        unique=True,
        postgresql_where=sa.text("role = 'excavator'"),
        sqlite_where=sa.text("role = 'excavator'"),
    )
    op.create_index(
        "uq_user_site_one_exhauster",
        "user_site",
        ["site_id"],
        unique=True,
        postgresql_where=sa.text("role = 'exhauster'"),
        sqlite_where=sa.text("role = 'exhauster'"),
    )

    op.drop_index("ix_site_status_timestamp", table_name="site_status")
    op.drop_index("ix_site_status_site_id", table_name="site_status")
    op.drop_table("site_status")


def downgrade() -> None:
    op.create_table(
        "site_status",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("site_id", sa.Integer(), nullable=False),
        sa.Column(
            "timestamp",
            sa.DateTime(timezone=True),
            server_default=sa.text("CURRENT_TIMESTAMP"),
            nullable=False,
        ),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.ForeignKeyConstraint(["site_id"], ["site.site_id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_site_status_site_id", "site_status", ["site_id"])
    op.create_index("ix_site_status_timestamp", "site_status", ["timestamp"])

    op.drop_index("uq_user_site_one_exhauster", table_name="user_site")
    op.drop_index("uq_user_site_one_excavator", table_name="user_site")
    op.drop_index("ix_user_site_site_id_timestamp", table_name="user_site")
    op.drop_index("ix_user_site_timestamp", table_name="user_site")
    op.drop_index("ix_user_site_site_id", table_name="user_site")
    op.drop_index("ix_user_site_user_id", table_name="user_site")
    op.drop_table("user_site")
