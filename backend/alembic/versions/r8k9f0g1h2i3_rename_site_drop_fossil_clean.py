"""rename site_clean to site, drop fossil_clean, add fossil.site_id

Revision ID: r8k9f0g1h2i3
Revises: q7j8e9f0g1h2
Create Date: 2026-07-14 09:30:00.000000

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "r8k9f0g1h2i3"
down_revision: Union[str, None] = "q7j8e9f0g1h2"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.rename_table("site_clean", "site")
    op.execute(
        sa.text("ALTER INDEX IF EXISTS ix_site_clean_site_type_id RENAME TO ix_site_site_type_id")
    )
    op.execute(
        sa.text(
            "ALTER TABLE site RENAME CONSTRAINT fk_site_clean_site_type_id "
            "TO fk_site_site_type_id"
        )
    )

    op.add_column("fossil", sa.Column("site_id", sa.Integer(), nullable=True))
    op.create_index(op.f("ix_fossil_site_id"), "fossil", ["site_id"], unique=False)

    op.execute(
        sa.text(
            """
            UPDATE fossil AS f
            SET site_id = fc.site_id
            FROM fossil_clean AS fc
            WHERE f.id = fc.fossil_id
            """
        )
    )
    op.execute(
        sa.text(
            """
            UPDATE fossil
            SET site_id = collection_no
            WHERE site_id IS NULL AND collection_no IS NOT NULL
            """
        )
    )

    op.drop_index(op.f("ix_fossil_clean_site_id"), table_name="fossil_clean")
    op.drop_index(op.f("ix_fossil_clean_dinosaur_id"), table_name="fossil_clean")
    op.drop_table("fossil_clean")

    op.create_foreign_key(
        "fk_fossil_site_id",
        "fossil",
        "site",
        ["site_id"],
        ["site_id"],
        ondelete="SET NULL",
    )


def downgrade() -> None:
    op.drop_constraint("fk_fossil_site_id", "fossil", type_="foreignkey")
    op.drop_index(op.f("ix_fossil_site_id"), table_name="fossil")
    op.drop_column("fossil", "site_id")

    op.create_table(
        "fossil_clean",
        sa.Column("fossil_id", sa.Integer(), nullable=False),
        sa.Column("site_id", sa.Integer(), nullable=False),
        sa.Column("dinosaur_id", sa.Integer(), nullable=False),
        sa.Column("name", sa.String(length=255), nullable=True),
        sa.Column("type", sa.String(length=20), nullable=False),
        sa.Column("sub_category", sa.String(length=255), nullable=True),
        sa.Column("preservation_quality", sa.String(length=50), nullable=True),
        sa.Column("min_age_ma", sa.Numeric(precision=5, scale=2), nullable=True),
        sa.Column("max_age_ma", sa.Numeric(precision=5, scale=2), nullable=True),
        sa.Column("collection_year_min", sa.Integer(), nullable=True),
        sa.Column("collection_year_max", sa.Integer(), nullable=True),
        sa.Column("comment", sa.Text(), nullable=True),
        sa.ForeignKeyConstraint(["dinosaur_id"], ["dinosaur.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["fossil_id"], ["fossil.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["site_id"], ["site.site_id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("fossil_id"),
    )
    op.create_index(op.f("ix_fossil_clean_dinosaur_id"), "fossil_clean", ["dinosaur_id"], unique=False)
    op.create_index(op.f("ix_fossil_clean_site_id"), "fossil_clean", ["site_id"], unique=False)

    op.rename_table("site", "site_clean")
    op.execute(
        sa.text("ALTER INDEX IF EXISTS ix_site_site_type_id RENAME TO ix_site_clean_site_type_id")
    )
    op.execute(
        sa.text(
            "ALTER TABLE site_clean RENAME CONSTRAINT fk_site_site_type_id "
            "TO fk_site_clean_site_type_id"
        )
    )
