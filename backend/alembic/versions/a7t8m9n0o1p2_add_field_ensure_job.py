"""add field ensure job queue, site geo index, field site id sequence

Revision ID: a7t8m9n0o1p2
Revises: z6s7l8m9n0o1
Create Date: 2026-07-18 13:35:00.000000

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "a7t8m9n0o1p2"
down_revision: Union[str, None] = "z6s7l8m9n0o1"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    bind = op.get_bind()
    if bind.dialect.name == "postgresql":
        op.execute(
            sa.text(
                "CREATE SEQUENCE IF NOT EXISTS field_site_id_seq "
                "START WITH 1000000000 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1"
            )
        )

    op.create_table(
        "field_ensure_job",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("cell_key", sa.String(length=64), nullable=False),
        sa.Column("lat", sa.Float(), nullable=False),
        sa.Column("lon", sa.Float(), nullable=False),
        sa.Column("radius_km", sa.Float(), nullable=False),
        sa.Column("missing_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("status", sa.String(length=16), nullable=False, server_default="pending"),
        sa.Column("attempts", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("worker_id", sa.String(length=64), nullable=True),
        sa.Column("error_message", sa.String(length=2000), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("started_at", sa.DateTime(), nullable=True),
        sa.Column("finished_at", sa.DateTime(), nullable=True),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("cell_key"),
    )
    op.create_index(
        "ix_field_ensure_job_status_created_at",
        "field_ensure_job",
        ["status", "created_at"],
    )

    op.create_index(
        "ix_site_data_source_latitude_longitude",
        "site",
        ["data_source", "latitude", "longitude"],
    )


def downgrade() -> None:
    op.drop_index("ix_site_data_source_latitude_longitude", table_name="site")
    op.drop_index("ix_field_ensure_job_status_created_at", table_name="field_ensure_job")
    op.drop_table("field_ensure_job")

    bind = op.get_bind()
    if bind.dialect.name == "postgresql":
        op.execute(sa.text("DROP SEQUENCE IF EXISTS field_site_id_seq"))
