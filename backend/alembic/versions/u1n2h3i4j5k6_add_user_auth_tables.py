"""add user auth and social tables

Revision ID: u1n2h3i4j5k6
Revises: t0m1h2i3j4k5
Create Date: 2026-07-15 08:55:00.000000

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "u1n2h3i4j5k6"
down_revision: Union[str, None] = "t0m1h2i3j4k5"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "user",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("username", sa.String(length=50), nullable=False),
        sa.Column("email", sa.String(length=255), nullable=False),
        sa.Column("password", sa.String(length=128), nullable=True),
        sa.Column("firebase_uid", sa.String(), nullable=True),
        sa.Column("unlinked_firebase_providers", sa.String(length=255), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("full_name", sa.String(length=200), nullable=True),
        sa.Column("image_url", sa.String(length=2048), nullable=True),
        sa.Column("display_name", sa.String(length=200), nullable=False),
        sa.Column("specialization", sa.String(length=200), nullable=False),
        sa.Column("years_of_experience", sa.Integer(), nullable=False),
        sa.Column("notable_discovery", sa.String(length=500), nullable=False),
        sa.Column("favorite_era", sa.String(length=200), nullable=False),
        sa.Column("xp", sa.Integer(), nullable=False),
        sa.Column("level", sa.Integer(), nullable=False),
        sa.Column("achievements", sa.JSON(), nullable=False),
        sa.Column("bio", sa.String(length=2000), nullable=False),
        sa.Column("current_location", sa.String(length=200), nullable=False),
        sa.Column("is_admin", sa.Boolean(), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_user_username"), "user", ["username"], unique=True)
    op.create_index(op.f("ix_user_email"), "user", ["email"], unique=True)
    op.create_index(op.f("ix_user_firebase_uid"), "user", ["firebase_uid"], unique=True)

    op.create_table(
        "user_auth_identity",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("provider", sa.String(length=32), nullable=False),
        sa.Column("provider_user_id", sa.String(length=255), nullable=False),
        sa.Column("email", sa.String(length=255), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["user.id"]),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "provider",
            "provider_user_id",
            name="uq_user_auth_identity_provider_provider_user_id",
        ),
    )
    op.create_index(
        op.f("ix_user_auth_identity_user_id"),
        "user_auth_identity",
        ["user_id"],
        unique=False,
    )
    op.create_index(
        op.f("ix_user_auth_identity_provider"),
        "user_auth_identity",
        ["provider"],
        unique=False,
    )
    op.create_index(
        op.f("ix_user_auth_identity_provider_user_id"),
        "user_auth_identity",
        ["provider_user_id"],
        unique=False,
    )

    op.create_table(
        "user_user",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("user_id1", sa.Integer(), nullable=False),
        sa.Column("user_id2", sa.Integer(), nullable=False),
        sa.Column("relationship_type", sa.String(length=32), nullable=False),
        sa.Column("action_user_id", sa.Integer(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["action_user_id"], ["user.id"]),
        sa.ForeignKeyConstraint(["user_id1"], ["user.id"]),
        sa.ForeignKeyConstraint(["user_id2"], ["user.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_user_user_user_id1"), "user_user", ["user_id1"], unique=False)
    op.create_index(op.f("ix_user_user_user_id2"), "user_user", ["user_id2"], unique=False)
    op.create_index(
        op.f("ix_user_user_relationship_type"),
        "user_user",
        ["relationship_type"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index(op.f("ix_user_user_relationship_type"), table_name="user_user")
    op.drop_index(op.f("ix_user_user_user_id2"), table_name="user_user")
    op.drop_index(op.f("ix_user_user_user_id1"), table_name="user_user")
    op.drop_table("user_user")
    op.drop_index(
        op.f("ix_user_auth_identity_provider_user_id"),
        table_name="user_auth_identity",
    )
    op.drop_index(op.f("ix_user_auth_identity_provider"), table_name="user_auth_identity")
    op.drop_index(op.f("ix_user_auth_identity_user_id"), table_name="user_auth_identity")
    op.drop_table("user_auth_identity")
    op.drop_index(op.f("ix_user_firebase_uid"), table_name="user")
    op.drop_index(op.f("ix_user_email"), table_name="user")
    op.drop_index(op.f("ix_user_username"), table_name="user")
    op.drop_table("user")
