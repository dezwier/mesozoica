"""add tool default/instance params json

Revision ID: r1s2t3u4v5w6
Revises: q9r0s1t2u3v4
Create Date: 2026-07-29 10:50:00.000000

"""

from __future__ import annotations

import json
from typing import Any, Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "r1s2t3u4v5w6"
down_revision: Union[str, None] = "q9r0s1t2u3v4"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _defaults_by_tool_name() -> dict[str, dict[str, Any]]:
    from app.core.game_config import get_game_config

    cfg = get_game_config().tool_actions
    return {
        "Aerial Recon": cfg.aerial_recon.model_dump(mode="json"),
        "Aerial Scout": cfg.aerial_scout.model_dump(mode="json"),
        "Geo Compass": cfg.geo_compass.model_dump(mode="json"),
        "Proximity Scanner": cfg.proximity_scanner.model_dump(mode="json"),
        "Site Navigator": cfg.site_navigator.model_dump(mode="json"),
        "Formation Map": cfg.formation_map.model_dump(mode="json"),
    }


def upgrade() -> None:
    op.add_column(
        "tool_type",
        sa.Column(
            "default_params_json",
            sa.JSON(),
            nullable=False,
            server_default=sa.text("'{}'"),
        ),
    )
    op.add_column(
        "tool",
        sa.Column(
            "params_json",
            sa.JSON(),
            nullable=False,
            server_default=sa.text("'{}'"),
        ),
    )

    bind = op.get_bind()
    tool_type = sa.table(
        "tool_type",
        sa.column("id", sa.Integer()),
        sa.column("name", sa.String()),
        sa.column("default_params_json", sa.JSON()),
    )
    tool = sa.table(
        "tool",
        sa.column("id", sa.Integer()),
        sa.column("tool_type_id", sa.Integer()),
        sa.column("params_json", sa.JSON()),
    )

    defaults = _defaults_by_tool_name()
    rows = bind.execute(sa.select(tool_type.c.id, tool_type.c.name)).fetchall()
    for tool_type_id, name in rows:
        payload = defaults.get(str(name), {})
        bind.execute(
            sa.update(tool_type)
            .where(tool_type.c.id == int(tool_type_id))
            .values(default_params_json=payload)
        )

    instance_rows = bind.execute(
        sa.select(tool.c.id, tool.c.tool_type_id, tool_type.c.default_params_json).select_from(
            tool.join(tool_type, tool.c.tool_type_id == tool_type.c.id)
        )
    ).fetchall()
    for tool_id, _tool_type_id, default_payload in instance_rows:
        payload = default_payload if isinstance(default_payload, dict) else {}
        bind.execute(
            sa.update(tool).where(tool.c.id == int(tool_id)).values(params_json=payload)
        )

    op.alter_column("tool_type", "default_params_json", server_default=None)
    op.alter_column("tool", "params_json", server_default=None)


def downgrade() -> None:
    op.drop_column("tool", "params_json")
    op.drop_column("tool_type", "default_params_json")
