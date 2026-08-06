"""Admin collect helper: spawn a tool instance and record ownership."""

from __future__ import annotations

from datetime import datetime, timezone

from sqlmodel import Session, col, select

from app.core.exceptions import NotFoundError, ValidationError
from app.models.tool import Tool
from app.models.tool_type import ToolType
from app.models.user_tool import USER_TOOL_ACTION_OWNED, UserTool
from app.features.media.public import (
    is_version_dir_name,
    latest_tool_image_version,
    load_image_versions,
    normalize_version_name,
)
from app.features.tools.application.catalog.params import base_params_for_tool_type


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _owned_instance_for_type(
    session: Session,
    *,
    user_id: int,
    tool_type_id: int,
) -> Tool | None:
    """Return the user's owned instance for a type (highest level, then newest)."""
    rows = session.exec(
        select(Tool)
        .join(UserTool, col(UserTool.tool_id) == col(Tool.id))
        .where(
            col(UserTool.user_id) == user_id,
            col(UserTool.action) == USER_TOOL_ACTION_OWNED,
            col(Tool.tool_type_id) == tool_type_id,
        )
        .order_by(col(Tool.level).desc(), col(Tool.spawn_date).desc())
    ).all()
    return rows[0] if rows else None


def list_tool_image_versions() -> list[dict[str, str | None]]:
    """Available curated tool image version folders for admin collect UI."""
    from app.core.config import settings

    versions = load_image_versions(settings.resolved_tool_images_dir)
    # Newest first for picker convenience.
    ordered = sorted(
        versions,
        key=lambda v: (
            v.run_date is not None,
            v.run_date or datetime.min.replace(tzinfo=timezone.utc),
            v.name.lower(),
        ),
        reverse=True,
    )
    return [
        {
            "name": v.name,
            "run_date": v.run_date.isoformat() if v.run_date else None,
        }
        for v in ordered
    ]


def _resolve_collect_version(version: str | None) -> str:
    from app.core.config import settings

    if version is None or not str(version).strip():
        return latest_tool_image_version()
    name = normalize_version_name(version)
    root = settings.resolved_tool_images_dir
    known = {v.name for v in load_image_versions(root)}
    if known and name not in known:
        raise ValidationError(
            f"Unknown tool image version {name!r}; available: {sorted(known)}"
        )
    if not is_version_dir_name(name):
        raise ValidationError(f"Invalid tool image version {name!r}")
    return name


def collect_tool_for_user(
    session: Session,
    *,
    user_id: int,
    tool_id: int,
    version: str | None = None,
) -> tuple[ToolType, int]:
    """Spawn a new owned instance of catalog ``tool_id`` (tool_type id).

    Always creates a new occurrence (admins may collect duplicates). When
    ``version`` is omitted, uses the latest curated image version by run_date.
    """
    tool_type = session.get(ToolType, tool_id)
    if tool_type is None:
        raise NotFoundError(f"Tool {tool_id} not found")

    image_version = _resolve_collect_version(version)

    now = _utc_now()
    instance = Tool(
        tool_type_id=tool_id,
        spawn_date=now,
        level=1,
        version=image_version,
        params_json=base_params_for_tool_type(tool_type),
    )
    session.add(instance)
    session.flush()
    session.add(
        UserTool(
            user_id=user_id,
            tool_id=int(instance.id),
            timestamp=now,
            action=USER_TOOL_ACTION_OWNED,
        )
    )
    session.commit()
    session.refresh(instance)
    # Catalog cards annotate the highest owned level for the type.
    levels = ownership_levels_for_tool_types(
        session, user_id=user_id, tool_type_ids=[tool_id]
    )
    return tool_type, levels.get(tool_id, int(instance.level))


def ownership_levels_for_tool_types(
    session: Session,
    *,
    user_id: int,
    tool_type_ids: list[int],
) -> dict[int, int]:
    """Map tool_type_id → level for the given user among ``tool_type_ids``.

    When multiple instances exist for a type, the highest level wins.
    """
    if not tool_type_ids:
        return {}
    rows = session.exec(
        select(Tool.tool_type_id, Tool.level)
        .join(UserTool, col(UserTool.tool_id) == col(Tool.id))
        .where(
            col(UserTool.user_id) == user_id,
            col(UserTool.action) == USER_TOOL_ACTION_OWNED,
            col(Tool.tool_type_id).in_(tool_type_ids),
        )
    ).all()
    levels: dict[int, int] = {}
    for tool_type_id, level in rows:
        tid = int(tool_type_id)
        lvl = int(level)
        if tid not in levels or lvl > levels[tid]:
            levels[tid] = lvl
    return levels


def resolve_owned_instance(
    session: Session,
    *,
    user_id: int,
    tool_type_id: int,
) -> Tool | None:
    """Public helper: owned instance for a catalog tool type, if any."""
    return _owned_instance_for_type(
        session, user_id=user_id, tool_type_id=tool_type_id
    )


def resolve_owned_tool_selection(
    session: Session,
    *,
    user_id: int,
    tool_id: int,
) -> tuple[ToolType, Tool] | None:
    """Resolve a user's selected tool interaction target.

    Inventory interactions operate on ``tool`` occurrences. To keep the API
    compatible, accept either:
    - a concrete owned ``tool.id`` instance id, or
    - a ``tool_type.id`` and resolve the user's owned instance of that type.
    """
    instance = session.get(Tool, tool_id)
    if instance is not None:
        owned = session.exec(
            select(UserTool)
            .where(
                col(UserTool.user_id) == user_id,
                col(UserTool.tool_id) == int(instance.id),
                col(UserTool.action) == USER_TOOL_ACTION_OWNED,
            )
            .order_by(col(UserTool.timestamp).desc())
        ).first()
        if owned is not None:
            tool_type = session.get(ToolType, int(instance.tool_type_id))
            if tool_type is not None:
                return tool_type, instance

    tool_type = session.get(ToolType, tool_id)
    if tool_type is None:
        return None
    instance = resolve_owned_instance(
        session, user_id=user_id, tool_type_id=int(tool_type.id)
    )
    if instance is None:
        return None
    return tool_type, instance


# Back-compat alias used by older call sites / tests.
ownership_levels_for_tools = ownership_levels_for_tool_types
