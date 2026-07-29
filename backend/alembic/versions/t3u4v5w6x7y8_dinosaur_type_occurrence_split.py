"""rename dinosaur→dinosaur_type, add dinosaur occurrences, remap user_dinosaur

Revision ID: t3u4v5w6x7y8
Revises: s2t3u4v5w6x7
Create Date: 2026-07-29 17:40:00.000000

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "t3u4v5w6x7y8"
down_revision: Union[str, None] = "s2t3u4v5w6x7"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _drop_fks_to_table(table_name: str, referred_table: str) -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    for fk in inspector.get_foreign_keys(table_name):
        if fk.get("referred_table") == referred_table and fk.get("name"):
            op.drop_constraint(fk["name"], table_name, type_="foreignkey")


def upgrade() -> None:
    _drop_fks_to_table("fossil", "dinosaur")
    _drop_fks_to_table("user_dinosaur", "dinosaur")

    op.rename_table("dinosaur", "dinosaur_type")

    # Rename common indexes if present (Postgres).
    op.execute(
        sa.text("ALTER INDEX IF EXISTS ix_dinosaur_name RENAME TO ix_dinosaur_type_name")
    )
    op.execute(
        sa.text(
            "ALTER INDEX IF EXISTS ix_dinosaur_wikipedia_page_id "
            "RENAME TO ix_dinosaur_type_wikipedia_page_id"
        )
    )
    op.execute(
        sa.text(
            "ALTER INDEX IF EXISTS ix_dinosaur_llm_enriched "
            "RENAME TO ix_dinosaur_type_llm_enriched"
        )
    )

    op.create_foreign_key(
        "fossil_dinosaur_id_fkey",
        "fossil",
        "dinosaur_type",
        ["dinosaur_id"],
        ["id"],
        ondelete="CASCADE",
    )

    op.create_table(
        "dinosaur",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("dinosaur_type_id", sa.Integer(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("CURRENT_TIMESTAMP"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(
            ["dinosaur_type_id"],
            ["dinosaur_type.id"],
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_dinosaur_dinosaur_type_id", "dinosaur", ["dinosaur_type_id"])
    op.create_index("ix_dinosaur_created_at", "dinosaur", ["created_at"])

    # Existing user_dinosaur rows pointed at catalog genera — clear them.
    op.execute(sa.text("DELETE FROM user_dinosaur"))

    op.create_foreign_key(
        "user_dinosaur_dinosaur_id_fkey",
        "user_dinosaur",
        "dinosaur",
        ["dinosaur_id"],
        ["id"],
        ondelete="CASCADE",
    )


def downgrade() -> None:
    _drop_fks_to_table("user_dinosaur", "dinosaur")
    op.execute(sa.text("DELETE FROM user_dinosaur"))

    op.drop_index("ix_dinosaur_created_at", table_name="dinosaur")
    op.drop_index("ix_dinosaur_dinosaur_type_id", table_name="dinosaur")
    op.drop_table("dinosaur")

    _drop_fks_to_table("fossil", "dinosaur_type")

    op.execute(
        sa.text(
            "ALTER INDEX IF EXISTS ix_dinosaur_type_llm_enriched "
            "RENAME TO ix_dinosaur_llm_enriched"
        )
    )
    op.execute(
        sa.text(
            "ALTER INDEX IF EXISTS ix_dinosaur_type_wikipedia_page_id "
            "RENAME TO ix_dinosaur_wikipedia_page_id"
        )
    )
    op.execute(
        sa.text("ALTER INDEX IF EXISTS ix_dinosaur_type_name RENAME TO ix_dinosaur_name")
    )
    op.rename_table("dinosaur_type", "dinosaur")

    op.create_foreign_key(
        "fossil_dinosaur_id_fkey",
        "fossil",
        "dinosaur",
        ["dinosaur_id"],
        ["id"],
        ondelete="CASCADE",
    )
    op.create_foreign_key(
        "user_dinosaur_dinosaur_id_fkey",
        "user_dinosaur",
        "dinosaur",
        ["dinosaur_id"],
        ["id"],
        ondelete="CASCADE",
    )
