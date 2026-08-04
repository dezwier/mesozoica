"""Merge 12 skills into field_survey / bone_quarry / science_hall.

Revision ID: k0l1m2n3o4p5
Revises: j9k0l1m2n3o4
Create Date: 2026-08-04 23:50:00.000000

"""

from __future__ import annotations

import json
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

from app.services.level_service.skill_merge import (
    merge_skill_breakdown,
    merge_skill_xp,
)

revision: str = "k0l1m2n3o4p5"
down_revision: Union[str, None] = "j9k0l1m2n3o4"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_CATEGORY_MAP: dict[str, str] = {
    "1 site_discovery": "1 field_survey",
    "2 site_stewardship": "1 field_survey",
    "3 site_clearing": "1 field_survey",
    "4 fossil_detection": "2 bone_quarry",
    "5 fossil_excavation": "2 bone_quarry",
    "6 fossil_transport": "2 bone_quarry",
    "7 fossil_curation": "2 bone_quarry",
    "8 fossil_preparation": "3 science_hall",
    "9 fossil_analysis": "3 science_hall",
    "10 dinosaur_modelling": "3 science_hall",
    "11 dinosaur_mounting": "3 science_hall",
    "12 academic_publishing": "3 science_hall",
}


def upgrade() -> None:
    conn = op.get_bind()
    rows = conn.execute(
        sa.text('SELECT id, skill_xp, skill_breakdown FROM "user"')
    ).mappings()
    for row in rows:
        new_xp = merge_skill_xp(row["skill_xp"])
        new_bd = merge_skill_breakdown(row["skill_breakdown"])
        conn.execute(
            sa.text(
                'UPDATE "user" SET skill_xp = CAST(:xp AS jsonb), '
                "skill_breakdown = CAST(:bd AS jsonb) WHERE id = :id"
            ),
            {
                "id": row["id"],
                "xp": json.dumps(new_xp),
                "bd": json.dumps(new_bd),
            },
        )

    for old, new in _CATEGORY_MAP.items():
        conn.execute(
            sa.text(
                "UPDATE tool_type SET category = :new WHERE category = :old"
            ),
            {"old": old, "new": new},
        )


def downgrade() -> None:
    # Irreversible XP merge; restore category labels only where unambiguous.
    reverse = {
        "1 field_survey": "1 site_discovery",
        "2 bone_quarry": "4 fossil_detection",
        "3 science_hall": "9 fossil_analysis",
    }
    conn = op.get_bind()
    for old, new in reverse.items():
        conn.execute(
            sa.text(
                "UPDATE tool_type SET category = :new WHERE category = :old"
            ),
            {"old": old, "new": new},
        )
