"""Add game config revision history and active release pointer.

Revision ID: j9k0l1m2n3o4
Revises: i8j9k0l1m2n3
Create Date: 2026-08-04 16:00:00.000000

Schema only. Seeding from the YAML control board is the ``game_config_seed``
cron job (``make run-game-config-seed``), matching how tool/site data is loaded.

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "j9k0l1m2n3o4"
down_revision: Union[str, None] = "i8j9k0l1m2n3"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "game_config_revision",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("version", sa.Integer(), nullable=False),
        sa.Column("documents", sa.JSON(), nullable=False),
        sa.Column("checksum", sa.String(length=64), nullable=False),
        sa.Column("source", sa.String(length=16), nullable=False, server_default="admin"),
        sa.Column("note", sa.Text(), nullable=False, server_default=""),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("CURRENT_TIMESTAMP"),
        ),
        sa.Column("created_by_user_id", sa.Integer(), nullable=True),
        sa.ForeignKeyConstraint(
            ["created_by_user_id"], ["user.id"], ondelete="SET NULL"
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        op.f("ix_game_config_revision_version"),
        "game_config_revision",
        ["version"],
        unique=True,
    )
    op.create_index(
        op.f("ix_game_config_revision_checksum"),
        "game_config_revision",
        ["checksum"],
    )
    op.create_index(
        op.f("ix_game_config_revision_created_at"),
        "game_config_revision",
        ["created_at"],
    )

    op.create_table(
        "game_config_release",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("active_version", sa.Integer(), nullable=False),
        sa.Column("active_checksum", sa.String(length=64), nullable=False),
        sa.Column("revision_id", sa.Integer(), nullable=False),
        sa.Column(
            "activated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("CURRENT_TIMESTAMP"),
        ),
        sa.Column("activated_by_user_id", sa.Integer(), nullable=True),
        sa.CheckConstraint("id = 1", name="ck_game_config_release_singleton"),
        sa.ForeignKeyConstraint(
            ["revision_id"], ["game_config_revision.id"], ondelete="RESTRICT"
        ),
        sa.ForeignKeyConstraint(
            ["activated_by_user_id"], ["user.id"], ondelete="SET NULL"
        ),
        sa.PrimaryKeyConstraint("id"),
    )


def downgrade() -> None:
    op.drop_table("game_config_release")
    op.drop_index(
        op.f("ix_game_config_revision_created_at"), table_name="game_config_revision"
    )
    op.drop_index(
        op.f("ix_game_config_revision_checksum"), table_name="game_config_revision"
    )
    op.drop_index(
        op.f("ix_game_config_revision_version"), table_name="game_config_revision"
    )
    op.drop_table("game_config_revision")
