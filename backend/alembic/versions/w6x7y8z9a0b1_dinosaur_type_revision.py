"""Add dinosaur_type_revision; move content off dinosaur_type.

Revision ID: w6x7y8z9a0b1
Revises: v5w6x7y8z9a0
Create Date: 2026-07-31 22:55:00.000000

"""

from __future__ import annotations

import hashlib
import json
import re
from typing import Any, Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "w6x7y8z9a0b1"
down_revision: Union[str, None] = "v5w6x7y8z9a0"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_WHITESPACE_RE = re.compile(r"\s+")


def _content_hash(
    *,
    article: str | None,
    long_description: str | None,
    birth: float | None,
    death: float | None,
    period: str | None,
    diet_type: str | None,
    cladogram: Any,
) -> str:
    """Keep in sync with app.services.wikipedia_service.content_hash.revision_content_hash."""
    if isinstance(cladogram, str):
        try:
            cladogram_obj = json.loads(cladogram)
        except json.JSONDecodeError:
            cladogram_obj = {}
    else:
        cladogram_obj = cladogram or {}
    payload = {
        "article": _WHITESPACE_RE.sub(" ", article or "").strip(),
        "long_description": (long_description or "").strip(),
        "birth": birth,
        "death": death,
        "period": (period or "").strip(),
        "diet_type": (diet_type or "").strip().lower(),
        "cladogram": cladogram_obj,
    }
    raw = json.dumps(payload, sort_keys=True, ensure_ascii=False, separators=(",", ":"))
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def upgrade() -> None:
    op.create_table(
        "dinosaur_type_revision",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("dinosaur_type_id", sa.Integer(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("CURRENT_TIMESTAMP"),
            nullable=False,
        ),
        sa.Column("wikipedia_revision_id", sa.Integer(), nullable=True),
        sa.Column("article_date", sa.DateTime(timezone=True), nullable=True),
        sa.Column("content_hash", sa.String(length=64), nullable=False),
        sa.Column("birth", sa.Float(), nullable=True),
        sa.Column("death", sa.Float(), nullable=True),
        sa.Column("period", sa.String(length=255), nullable=True),
        sa.Column("cladogram", sa.JSON(), nullable=False),
        sa.Column("diet_type", sa.String(length=64), nullable=True),
        sa.Column("long_description", sa.Text(), nullable=True),
        sa.Column("article", sa.Text(), nullable=True),
        sa.Column("length", sa.String(length=128), nullable=True),
        sa.Column("mass", sa.String(length=128), nullable=True),
        sa.Column("location", sa.String(length=512), nullable=True),
        sa.Column("short_description", sa.Text(), nullable=True),
        sa.Column(
            "llm_enriched",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("false"),
        ),
        sa.ForeignKeyConstraint(
            ["dinosaur_type_id"],
            ["dinosaur_type.id"],
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "dinosaur_type_id",
            "content_hash",
            name="uq_dinosaur_type_revision_type_hash",
        ),
    )
    op.create_index(
        "ix_dinosaur_type_revision_dinosaur_type_id",
        "dinosaur_type_revision",
        ["dinosaur_type_id"],
    )
    op.create_index(
        "ix_dinosaur_type_revision_created_at",
        "dinosaur_type_revision",
        ["created_at"],
    )
    op.create_index(
        "ix_dinosaur_type_revision_wikipedia_revision_id",
        "dinosaur_type_revision",
        ["wikipedia_revision_id"],
    )
    op.create_index(
        "ix_dinosaur_type_revision_content_hash",
        "dinosaur_type_revision",
        ["content_hash"],
    )
    op.create_index(
        "ix_dinosaur_type_revision_llm_enriched",
        "dinosaur_type_revision",
        ["llm_enriched"],
    )

    conn = op.get_bind()
    rows = conn.execute(
        sa.text(
            """
            SELECT
                id,
                insert_date,
                article_date,
                birth,
                death,
                period,
                cladogram,
                diet_type,
                long_description,
                article,
                length,
                mass,
                location,
                short_description,
                llm_enriched
            FROM dinosaur_type
            """
        )
    ).mappings().all()

    insert_revision = sa.text(
        """
        INSERT INTO dinosaur_type_revision (
            dinosaur_type_id,
            created_at,
            article_date,
            content_hash,
            birth,
            death,
            period,
            cladogram,
            diet_type,
            long_description,
            article,
            length,
            mass,
            location,
            short_description,
            llm_enriched
        ) VALUES (
            :dinosaur_type_id,
            COALESCE(:created_at, CURRENT_TIMESTAMP),
            :article_date,
            :content_hash,
            :birth,
            :death,
            :period,
            CAST(:cladogram AS json),
            :diet_type,
            :long_description,
            :article,
            :length,
            :mass,
            :location,
            :short_description,
            :llm_enriched
        )
        """
    )
    for row in rows:
        cladogram = row["cladogram"]
        if cladogram is None:
            cladogram_json = "{}"
        elif isinstance(cladogram, str):
            cladogram_json = cladogram
        else:
            cladogram_json = json.dumps(cladogram)
        conn.execute(
            insert_revision,
            {
                "dinosaur_type_id": row["id"],
                "created_at": row["insert_date"],
                "article_date": row["article_date"],
                "content_hash": _content_hash(
                    article=row["article"],
                    long_description=row["long_description"],
                    birth=row["birth"],
                    death=row["death"],
                    period=row["period"],
                    diet_type=row["diet_type"],
                    cladogram=cladogram,
                ),
                "birth": row["birth"],
                "death": row["death"],
                "period": row["period"],
                "cladogram": cladogram_json,
                "diet_type": row["diet_type"],
                "long_description": row["long_description"],
                "article": row["article"],
                "length": row["length"],
                "mass": row["mass"],
                "location": row["location"],
                "short_description": row["short_description"],
                "llm_enriched": bool(row["llm_enriched"]),
            },
        )

    op.add_column(
        "dinosaur_type",
        sa.Column("current_revision_id", sa.Integer(), nullable=True),
    )
    op.create_index(
        "ix_dinosaur_type_current_revision_id",
        "dinosaur_type",
        ["current_revision_id"],
    )
    op.create_foreign_key(
        "fk_dinosaur_type_current_revision_id",
        "dinosaur_type",
        "dinosaur_type_revision",
        ["current_revision_id"],
        ["id"],
        ondelete="SET NULL",
    )
    op.execute(
        sa.text(
            """
            UPDATE dinosaur_type dt
            SET current_revision_id = r.id
            FROM dinosaur_type_revision r
            WHERE r.dinosaur_type_id = dt.id
            """
        )
    )

    op.add_column(
        "dinosaur",
        sa.Column("dinosaur_type_revision_id", sa.Integer(), nullable=True),
    )
    op.create_index(
        "ix_dinosaur_dinosaur_type_revision_id",
        "dinosaur",
        ["dinosaur_type_revision_id"],
    )
    op.create_foreign_key(
        "fk_dinosaur_dinosaur_type_revision_id",
        "dinosaur",
        "dinosaur_type_revision",
        ["dinosaur_type_revision_id"],
        ["id"],
        ondelete="SET NULL",
    )
    op.execute(
        sa.text(
            """
            UPDATE dinosaur d
            SET dinosaur_type_revision_id = dt.current_revision_id
            FROM dinosaur_type dt
            WHERE d.dinosaur_type_id = dt.id
            """
        )
    )

    op.drop_index("ix_dinosaur_type_llm_enriched", table_name="dinosaur_type")
    op.drop_column("dinosaur_type", "birth")
    op.drop_column("dinosaur_type", "death")
    op.drop_column("dinosaur_type", "period")
    op.drop_column("dinosaur_type", "cladogram")
    op.drop_column("dinosaur_type", "diet_type")
    op.drop_column("dinosaur_type", "length")
    op.drop_column("dinosaur_type", "mass")
    op.drop_column("dinosaur_type", "location")
    op.drop_column("dinosaur_type", "short_description")
    op.drop_column("dinosaur_type", "long_description")
    op.drop_column("dinosaur_type", "article")
    op.drop_column("dinosaur_type", "article_date")
    op.drop_column("dinosaur_type", "llm_enriched")


def downgrade() -> None:
    op.add_column(
        "dinosaur_type",
        sa.Column(
            "llm_enriched",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("false"),
        ),
    )
    op.add_column("dinosaur_type", sa.Column("article_date", sa.DateTime(), nullable=True))
    op.add_column("dinosaur_type", sa.Column("article", sa.Text(), nullable=True))
    op.add_column("dinosaur_type", sa.Column("long_description", sa.Text(), nullable=True))
    op.add_column("dinosaur_type", sa.Column("short_description", sa.Text(), nullable=True))
    op.add_column(
        "dinosaur_type", sa.Column("location", sa.String(length=512), nullable=True)
    )
    op.add_column(
        "dinosaur_type", sa.Column("mass", sa.String(length=128), nullable=True)
    )
    op.add_column(
        "dinosaur_type", sa.Column("length", sa.String(length=128), nullable=True)
    )
    op.add_column(
        "dinosaur_type", sa.Column("diet_type", sa.String(length=64), nullable=True)
    )
    op.add_column(
        "dinosaur_type",
        sa.Column(
            "cladogram",
            sa.JSON(),
            nullable=False,
            server_default=sa.text("'{}'::json"),
        ),
    )
    op.add_column(
        "dinosaur_type", sa.Column("period", sa.String(length=255), nullable=True)
    )
    op.add_column("dinosaur_type", sa.Column("death", sa.Float(), nullable=True))
    op.add_column("dinosaur_type", sa.Column("birth", sa.Float(), nullable=True))
    op.create_index("ix_dinosaur_type_llm_enriched", "dinosaur_type", ["llm_enriched"])

    op.execute(
        sa.text(
            """
            UPDATE dinosaur_type dt
            SET
                birth = r.birth,
                death = r.death,
                period = r.period,
                cladogram = r.cladogram,
                diet_type = r.diet_type,
                long_description = r.long_description,
                article = r.article,
                article_date = r.article_date,
                length = r.length,
                mass = r.mass,
                location = r.location,
                short_description = r.short_description,
                llm_enriched = r.llm_enriched
            FROM dinosaur_type_revision r
            WHERE r.id = dt.current_revision_id
            """
        )
    )

    op.drop_constraint(
        "fk_dinosaur_dinosaur_type_revision_id", "dinosaur", type_="foreignkey"
    )
    op.drop_index("ix_dinosaur_dinosaur_type_revision_id", table_name="dinosaur")
    op.drop_column("dinosaur", "dinosaur_type_revision_id")

    op.drop_constraint(
        "fk_dinosaur_type_current_revision_id", "dinosaur_type", type_="foreignkey"
    )
    op.drop_index("ix_dinosaur_type_current_revision_id", table_name="dinosaur_type")
    op.drop_column("dinosaur_type", "current_revision_id")

    op.drop_index(
        "ix_dinosaur_type_revision_llm_enriched", table_name="dinosaur_type_revision"
    )
    op.drop_index(
        "ix_dinosaur_type_revision_content_hash", table_name="dinosaur_type_revision"
    )
    op.drop_index(
        "ix_dinosaur_type_revision_wikipedia_revision_id",
        table_name="dinosaur_type_revision",
    )
    op.drop_index(
        "ix_dinosaur_type_revision_created_at", table_name="dinosaur_type_revision"
    )
    op.drop_index(
        "ix_dinosaur_type_revision_dinosaur_type_id",
        table_name="dinosaur_type_revision",
    )
    op.drop_table("dinosaur_type_revision")
