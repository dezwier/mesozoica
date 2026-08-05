"""Rename explore_1km_passively breakdown key to explore_100m_passively.

Revision ID: n3o4p5q6r7s8
Revises: m2n3o4p5q6r7
Create Date: 2026-08-05 09:40:00.000000

"""

from __future__ import annotations

import json
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "n3o4p5q6r7s8"
down_revision: Union[str, None] = "m2n3o4p5q6r7"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_OLD = "explore_1km_passively"
_NEW = "explore_100m_passively"


def _remap_breakdown(raw: object, *, old: str, new: str) -> dict[str, dict[str, int]]:
    if not isinstance(raw, dict):
        return {}
    out: dict[str, dict[str, int]] = {}
    for skill_id, sources in raw.items():
        if not isinstance(sources, dict):
            continue
        merged: dict[str, int] = {}
        for key, amount in sources.items():
            mapped = new if str(key) == old else str(key)
            try:
                add = int(amount or 0)
            except (TypeError, ValueError):
                add = 0
            if add == 0:
                continue
            merged[mapped] = merged.get(mapped, 0) + add
        if merged:
            out[str(skill_id)] = merged
    return out


def upgrade() -> None:
    conn = op.get_bind()
    rows = conn.execute(
        sa.text('SELECT id, skill_breakdown FROM "user"')
    ).mappings()
    for row in rows:
        remapped = _remap_breakdown(row["skill_breakdown"], old=_OLD, new=_NEW)
        conn.execute(
            sa.text(
                'UPDATE "user" SET skill_breakdown = CAST(:bd AS jsonb) '
                "WHERE id = :id"
            ),
            {"bd": json.dumps(remapped), "id": row["id"]},
        )


def downgrade() -> None:
    conn = op.get_bind()
    rows = conn.execute(
        sa.text('SELECT id, skill_breakdown FROM "user"')
    ).mappings()
    for row in rows:
        remapped = _remap_breakdown(row["skill_breakdown"], old=_NEW, new=_OLD)
        conn.execute(
            sa.text(
                'UPDATE "user" SET skill_breakdown = CAST(:bd AS jsonb) '
                "WHERE id = :id"
            ),
            {"bd": json.dumps(remapped), "id": row["id"]},
        )
