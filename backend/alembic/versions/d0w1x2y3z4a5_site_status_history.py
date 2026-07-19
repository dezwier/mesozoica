"""convert site_status to append-only history with id PK

Revision ID: d0w1x2y3z4a5
Revises: c9v0w1x2y3z4
Create Date: 2026-07-19 11:00:00.000000

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "d0w1x2y3z4a5"
down_revision: Union[str, None] = "c9v0w1x2y3z4"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    bind = op.get_bind()
    if bind.dialect.name == "postgresql":
        op.execute(sa.text("ALTER TABLE site_status DROP CONSTRAINT site_status_pkey"))
        op.execute(sa.text("ALTER TABLE site_status ADD COLUMN id SERIAL"))
        op.execute(
            sa.text(
                "UPDATE site_status SET id = nextval(pg_get_serial_sequence('site_status', 'id')) "
                "WHERE id IS NULL"
            )
        )
        op.execute(sa.text("ALTER TABLE site_status ALTER COLUMN id SET NOT NULL"))
        op.execute(sa.text("ALTER TABLE site_status ADD PRIMARY KEY (id)"))
        op.create_index("ix_site_status_site_id", "site_status", ["site_id"])
        op.create_index("ix_site_status_timestamp", "site_status", ["timestamp"])
        return

    # SQLite / other: rebuild table
    op.create_table(
        "site_status__new",
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
    op.execute(
        sa.text(
            """
            INSERT INTO site_status__new (site_id, timestamp, status)
            SELECT site_id, timestamp, status FROM site_status
            """
        )
    )
    op.drop_table("site_status")
    op.rename_table("site_status__new", "site_status")
    op.create_index("ix_site_status_site_id", "site_status", ["site_id"])
    op.create_index("ix_site_status_timestamp", "site_status", ["timestamp"])


def downgrade() -> None:
    bind = op.get_bind()
    if bind.dialect.name == "postgresql":
        op.drop_index("ix_site_status_timestamp", table_name="site_status")
        op.drop_index("ix_site_status_site_id", table_name="site_status")
        op.execute(
            sa.text(
                """
                DELETE FROM site_status a
                USING site_status b
                WHERE a.site_id = b.site_id
                  AND a.timestamp < b.timestamp
                """
            )
        )
        op.execute(
            sa.text(
                """
                DELETE FROM site_status a
                USING site_status b
                WHERE a.site_id = b.site_id
                  AND a.id < b.id
                """
            )
        )
        op.execute(sa.text("ALTER TABLE site_status DROP CONSTRAINT site_status_pkey"))
        op.execute(sa.text("ALTER TABLE site_status DROP COLUMN id"))
        op.execute(sa.text("ALTER TABLE site_status ADD PRIMARY KEY (site_id)"))
        return

    op.create_table(
        "site_status__old",
        sa.Column("site_id", sa.Integer(), nullable=False),
        sa.Column(
            "timestamp",
            sa.DateTime(timezone=True),
            server_default=sa.text("CURRENT_TIMESTAMP"),
            nullable=False,
        ),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.ForeignKeyConstraint(["site_id"], ["site.site_id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("site_id"),
    )
    op.execute(
        sa.text(
            """
            INSERT INTO site_status__old (site_id, timestamp, status)
            SELECT site_id, MAX(timestamp), 
                   (SELECT s2.status FROM site_status s2
                    WHERE s2.site_id = site_status.site_id
                    ORDER BY s2.timestamp DESC, s2.id DESC LIMIT 1)
            FROM site_status
            GROUP BY site_id
            """
        )
    )
    op.drop_table("site_status")
    op.rename_table("site_status__old", "site_status")
