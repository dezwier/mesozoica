"""Rename skill_breakdown source keys to match renamed main_params.

Revision ID: l1m2n3o4p5q6
Revises: k0l1m2n3o4p5
Create Date: 2026-08-05 08:50:00.000000

"""

from __future__ import annotations

import json
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "l1m2n3o4p5q6"
down_revision: Union[str, None] = "k0l1m2n3o4p5"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

# Old breakdown / XP-source keys → new keys (aligned with main_params renames).
_KEY_MAP: dict[str, str] = {
    "sites": "discover_site",
    "first_discovery": "discover_site_as_first",
    "active_distance": "explore_100m_actively",
    "passive_distance": "explore_1km_passively",
    "disguise": "disguise_of_site",
    "site_exploration": "document_progress",
    "site_documentation": "document_site",
    "site_identification": "identify_site",
    "first_documentation": "document_site_as_first",
    "fossils": "locate_fossil_in_situ",
}


def _remap_breakdown(raw: object) -> dict[str, dict[str, int]]:
    if not isinstance(raw, dict):
        return {}
    out: dict[str, dict[str, int]] = {}
    for skill_id, sources in raw.items():
        if not isinstance(sources, dict):
            continue
        merged: dict[str, int] = {}
        for key, amount in sources.items():
            new_key = _KEY_MAP.get(str(key), str(key))
            try:
                add = int(amount or 0)
            except (TypeError, ValueError):
                add = 0
            if add == 0:
                continue
            merged[new_key] = merged.get(new_key, 0) + add
        if merged:
            out[str(skill_id)] = merged
    return out


def upgrade() -> None:
    conn = op.get_bind()
    rows = conn.execute(
        sa.text('SELECT id, skill_breakdown FROM "user"')
    ).mappings()
    for row in rows:
        remapped = _remap_breakdown(row["skill_breakdown"])
        conn.execute(
            sa.text(
                'UPDATE "user" SET skill_breakdown = CAST(:bd AS jsonb) '
                "WHERE id = :id"
            ),
            {"id": row["id"], "bd": json.dumps(remapped)},
        )


def downgrade() -> None:
    reverse = {v: k for k, v in _KEY_MAP.items()}
    conn = op.get_bind()
    rows = conn.execute(
        sa.text('SELECT id, skill_breakdown FROM "user"')
    ).mappings()
    for row in rows:
        raw = row["skill_breakdown"]
        if not isinstance(raw, dict):
            continue
        out: dict[str, dict[str, int]] = {}
        for skill_id, sources in raw.items():
            if not isinstance(sources, dict):
                continue
            merged: dict[str, int] = {}
            for key, amount in sources.items():
                old_key = reverse.get(str(key), str(key))
                try:
                    add = int(amount or 0)
                except (TypeError, ValueError):
                    add = 0
                if add == 0:
                    continue
                merged[old_key] = merged.get(old_key, 0) + add
            if merged:
                out[str(skill_id)] = merged
        conn.execute(
            sa.text(
                'UPDATE "user" SET skill_breakdown = CAST(:bd AS jsonb) '
                "WHERE id = :id"
            ),
            {"id": row["id"], "bd": json.dumps(out)},
        )
