"""surveyor role support, user_fossil, field_survey_job, field fossil id sequence

Revision ID: c9d0e1f2a3b4
Revises: b8c9d0e1f2a3
Create Date: 2026-07-20 10:40:00.000000

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "c9d0e1f2a3b4"
down_revision: Union[str, None] = "b8c9d0e1f2a3"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    bind = op.get_bind()
    if bind.dialect.name == "postgresql":
        op.execute(
            sa.text(
                "CREATE SEQUENCE IF NOT EXISTS field_fossil_id_seq "
                "START WITH 1000000000 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1"
            )
        )

    op.create_table(
        "user_fossil",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("fossil_id", sa.Integer(), nullable=False),
        sa.Column("role", sa.String(length=16), nullable=False),
        sa.Column(
            "timestamp",
            sa.DateTime(timezone=True),
            server_default=sa.text("CURRENT_TIMESTAMP"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(["fossil_id"], ["fossil.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["user_id"], ["user.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "user_id",
            "fossil_id",
            "role",
            name="uq_user_fossil_user_fossil_role",
        ),
    )
    op.create_index("ix_user_fossil_user_id", "user_fossil", ["user_id"])
    op.create_index("ix_user_fossil_fossil_id", "user_fossil", ["fossil_id"])
    op.create_index("ix_user_fossil_timestamp", "user_fossil", ["timestamp"])
    op.create_index(
        "ix_user_fossil_fossil_id_timestamp",
        "user_fossil",
        ["fossil_id", "timestamp"],
    )

    op.create_table(
        "field_survey_job",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("site_id", sa.Integer(), nullable=False),
        sa.Column("initiated_by_user_id", sa.Integer(), nullable=False),
        sa.Column(
            "status",
            sa.String(length=16),
            nullable=False,
            server_default="pending",
        ),
        sa.Column("fossil_count", sa.Integer(), nullable=True),
        sa.Column("attempts", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("worker_id", sa.String(length=64), nullable=True),
        sa.Column("error_message", sa.String(length=2000), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("started_at", sa.DateTime(), nullable=True),
        sa.Column("finished_at", sa.DateTime(), nullable=True),
        sa.ForeignKeyConstraint(["site_id"], ["site.site_id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(
            ["initiated_by_user_id"], ["user.id"], ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("site_id"),
    )
    op.create_index(
        "ix_field_survey_job_status_created_at",
        "field_survey_job",
        ["status", "created_at"],
    )
    op.create_index("ix_field_survey_job_site_id", "field_survey_job", ["site_id"])


def downgrade() -> None:
    op.drop_index("ix_field_survey_job_site_id", table_name="field_survey_job")
    op.drop_index(
        "ix_field_survey_job_status_created_at", table_name="field_survey_job"
    )
    op.drop_table("field_survey_job")

    op.drop_index("ix_user_fossil_fossil_id_timestamp", table_name="user_fossil")
    op.drop_index("ix_user_fossil_timestamp", table_name="user_fossil")
    op.drop_index("ix_user_fossil_fossil_id", table_name="user_fossil")
    op.drop_index("ix_user_fossil_user_id", table_name="user_fossil")
    op.drop_table("user_fossil")

    bind = op.get_bind()
    if bind.dialect.name == "postgresql":
        op.execute(sa.text("DROP SEQUENCE IF EXISTS field_fossil_id_seq"))
