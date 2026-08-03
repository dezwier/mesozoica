"""Timed overlay tool sessions (guidance, orbit, formation, terrain)."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any

from sqlmodel import Session, col, select

from app.core.exceptions import NotFoundError, ValidationError
from app.core.game_config import get_game_config
from app.models.tool_session import (
    ACTION_KEY_EXPEDITION_DRIVETRAIN,
    ACTION_KEY_FORMATION_MAP,
    ACTION_KEY_ORBIT_SURVEY,
    ACTION_KEY_RIDGE_GLASS,
    ACTION_KEY_TERRAIN_ECHO,
    LIVE_STATUSES,
    SESSION_STATUS_ACTIVE,
    SESSION_STATUS_CANCELLED,
    STOP_REASON_MANUAL,
    TIMED_OVERLAY_ACTION_KEYS,
    ToolSession,
)
from app.models.tool_type import ToolType
from app.models.user_tool import USER_TOOL_ACTION_DEPLOYED, UserTool
from app.services.field_service.field_ensure_queue import enqueue_field_site_ensure
from app.services.site_common.survey_grid import (
    footprint_for_center,
    snap_to_cell_center,
    snap_wideness_m,
)
from app.services.tool_action_service.guidance_kinds import (
    config_for_action_key as guidance_config_for_action_key,
    kind_for_tool_name as guidance_kind_for_tool_name,
    is_guidance_action_key,
)
from app.services.tool_action_service.tool_session.budget import (
    allocate_remaining_for_start,
)
from app.services.tool_action_service.tool_session.lifecycle import (
    close_session,
    ensure_exclusive_tool_session,
    expire_if_needed,
)
from app.services.tool_service.collect import resolve_owned_tool_selection

TOOL_NAME_ORBIT_SURVEY = "Orbit Survey"
TOOL_NAME_FORMATION_MAP = "Formation Map"
TOOL_NAME_TERRAIN_ECHO = "Terrain Echo"
TOOL_NAME_RIDGE_GLASS = "Ridge Glass"
TOOL_NAME_EXPEDITION_DRIVETRAIN = "Expedition Drivetrain"


def _utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


def _action_key_for_tool_name(tool_name: str) -> str:
    if tool_name == TOOL_NAME_ORBIT_SURVEY:
        return ACTION_KEY_ORBIT_SURVEY
    if tool_name == TOOL_NAME_FORMATION_MAP:
        return ACTION_KEY_FORMATION_MAP
    if tool_name == TOOL_NAME_TERRAIN_ECHO:
        return ACTION_KEY_TERRAIN_ECHO
    if tool_name == TOOL_NAME_RIDGE_GLASS:
        return ACTION_KEY_RIDGE_GLASS
    if tool_name == TOOL_NAME_EXPEDITION_DRIVETRAIN:
        return ACTION_KEY_EXPEDITION_DRIVETRAIN
    return guidance_kind_for_tool_name(tool_name).action_key


def _guidance_params(
    *,
    kind: Any,
    cfg: Any,
    inst_p: dict[str, Any],
    duration_minutes: int,
) -> dict[str, Any]:
    raw_mods = inst_p.get("modifies_main_params")
    if raw_mods is None:
        mods = getattr(cfg, "modifies_main_params", None)
        raw_mods = (
            mods.model_dump() if mods is not None and hasattr(mods, "model_dump") else mods
        )

    discovery_chance = None
    if kind.has_discovery_boost:
        raw_chance = inst_p.get("discovery_chance")
        if raw_chance is None and isinstance(raw_mods, dict):
            using = raw_mods.get("using") or {}
            skill = using.get("site_discovery") or {}
            entry = skill.get("discovery_chance") or {}
            if isinstance(entry, dict) and entry.get("op") == "replace":
                raw_chance = entry.get("value")
        if raw_chance is None:
            raw_chance = cfg.discovery_chance
        if raw_chance is not None:
            discovery_chance = float(raw_chance)

    direction_raw = (
        inst_p.get("direction_exactness")
        if inst_p.get("direction_exactness") is not None
        else inst_p.get("exactness")
    )
    distance_raw = (
        inst_p.get("distance_exactness")
        if inst_p.get("distance_exactness") is not None
        else inst_p.get("exactness")
    )
    direction_exactness = (
        float(direction_raw)
        if kind.show_needle and direction_raw is not None
        else (
            float(cfg.resolved_direction_exactness())
            if kind.show_needle
            else None
        )
    )
    distance_exactness = (
        float(distance_raw)
        if kind.show_distance and distance_raw is not None
        else (
            float(cfg.resolved_distance_exactness())
            if kind.show_distance
            else None
        )
    )
    params: dict[str, Any] = {"duration_minutes": duration_minutes}
    if discovery_chance is not None:
        params["discovery_chance"] = discovery_chance
    if raw_mods is not None:
        params["modifies_main_params"] = raw_mods
    if direction_exactness is not None:
        params["direction_exactness"] = direction_exactness
    if distance_exactness is not None:
        params["distance_exactness"] = distance_exactness
    return params


def _orbit_params(
    *,
    cfg: Any,
    inst_p: dict[str, Any],
    duration_minutes: int,
) -> dict[str, Any]:
    return {
        "duration_minutes": duration_minutes,
        "accuracy": float(inst_p.get("accuracy", cfg.accuracy)),
        "range": float(inst_p.get("range", cfg.range)),
        "min_range_m": float(inst_p.get("min_range_m", cfg.min_range_m)),
        "max_range_m": float(inst_p.get("max_range_m", cfg.max_range_m)),
    }


def _terrain_params(
    *,
    cfg: Any,
    inst_p: dict[str, Any],
    duration_minutes: int,
) -> dict[str, Any]:
    return {
        "duration_minutes": duration_minutes,
        "accuracy": float(inst_p.get("accuracy", cfg.accuracy)),
        "range_m": float(inst_p.get("range_m", cfg.range_m)),
    }


def _main_param_buff_params(
    *,
    cfg: Any,
    inst_p: dict[str, Any],
    duration_minutes: int,
) -> dict[str, Any]:
    """Snapshot duration + site_discovery buffs for an active timed buff tool."""
    raw_mods = inst_p.get("modifies_main_params")
    if raw_mods is None:
        mods = getattr(cfg, "modifies_main_params", None)
        raw_mods = (
            mods.model_dump() if mods is not None and hasattr(mods, "model_dump") else mods
        )
    params: dict[str, Any] = {"duration_minutes": duration_minutes}
    if raw_mods is not None:
        params["modifies_main_params"] = raw_mods
    return params


# Back-compat alias used by Ridge Glass tests / callers.
_ridge_glass_params = _main_param_buff_params


def _place_formation_center(
    session: Session,
    *,
    instance: Any,
    cfg: Any,
    lat: float | None,
    lon: float | None,
) -> tuple[dict[str, Any], float, float, float, float]:
    """Snap/persist center; return (inst_p, center_lat, center_lon, wideness, cell_size)."""
    game = get_game_config()
    inst_p = dict(instance.params_json or {})
    cell_size = float(game.site_generation.lazy.cell_size_m)
    wideness = snap_wideness_m(
        float(inst_p.get("wideness_m", cfg.wideness_m)),
        cell_size_m=cell_size,
        min_wideness_m=float(inst_p.get("min_wideness_m", cfg.min_wideness_m)),
        max_wideness_m=float(inst_p.get("max_wideness_m", cfg.max_wideness_m)),
    )

    center_lat = inst_p.get("center_lat")
    center_lon = inst_p.get("center_lon")
    if center_lat is None or center_lon is None:
        if lat is None or lon is None:
            raise ValidationError(
                "GPS coordinates are required to place a new Formation Map"
            )
        center_lat, center_lon = snap_to_cell_center(
            float(lat), float(lon), cell_size_m=cell_size
        )
        inst_p["center_lat"] = float(center_lat)
        inst_p["center_lon"] = float(center_lon)
        inst_p["wideness_m"] = float(wideness)
        inst_p["cell_size_m"] = float(cell_size)
        instance.params_json = inst_p
        session.add(instance)
    else:
        center_lat = float(center_lat)
        center_lon = float(center_lon)
        center_lat, center_lon = snap_to_cell_center(
            center_lat, center_lon, cell_size_m=cell_size
        )
        inst_p["cell_size_m"] = float(cell_size)
        instance.params_json = inst_p
        session.add(instance)

    return inst_p, float(center_lat), float(center_lon), float(wideness), cell_size


def _create_timed_row(
    session: Session,
    *,
    user_id: int,
    instance_id: int,
    action_key: str,
    params: dict[str, Any],
    remaining_s: int,
) -> ToolSession:
    now = _utcnow()
    row = ToolSession(
        user_id=user_id,
        tool_id=instance_id,
        action_key=action_key,
        status=SESSION_STATUS_ACTIVE,
        started_at=now,
        expires_at=now + timedelta(seconds=remaining_s),
        params_json=params,
        state_json={},
        created_at=now,
        updated_at=now,
    )
    session.add(row)
    session.add(
        UserTool(
            user_id=user_id,
            tool_id=instance_id,
            timestamp=datetime.now(timezone.utc),
            action=USER_TOOL_ACTION_DEPLOYED,
        )
    )
    session.commit()
    session.refresh(row)
    return row


def start_formation_session(
    session: Session,
    *,
    user_id: int,
    tool_id: int,
    lat: float | None = None,
    lon: float | None = None,
) -> ToolSession:
    """Validate ownership, snap/persist center on first use, snapshot knobs."""
    selected = resolve_owned_tool_selection(session, user_id=user_id, tool_id=tool_id)
    if selected is None:
        tool_type = session.get(ToolType, tool_id)
        if tool_type is None:
            raise NotFoundError(f"Tool {tool_id} not found")
        if tool_type.name != TOOL_NAME_FORMATION_MAP:
            raise ValidationError("This action is only available for Formation Map")
        raise ValidationError("You must own Formation Map to use it")
    tool_type, instance = selected
    if tool_type.name != TOOL_NAME_FORMATION_MAP:
        raise ValidationError("This action is only available for Formation Map")

    cfg = get_game_config().tool_actions.formation_map
    inst_p, center_lat, center_lon, wideness, cell_size = _place_formation_center(
        session,
        instance=instance,
        cfg=cfg,
        lat=lat,
        lon=lon,
    )

    footprint = footprint_for_center(
        float(center_lat),
        float(center_lon),
        wideness_m=wideness,
        cell_size_m=cell_size,
    )

    for cell_lat, cell_lon in footprint.cell_centers():
        enqueue_field_site_ensure(
            session,
            lat=cell_lat,
            lon=cell_lon,
            reason=ACTION_KEY_FORMATION_MAP,
        )

    ensure_exclusive_tool_session(
        session, user_id=user_id, instance_id=int(instance.id)
    )

    remaining_s = allocate_remaining_for_start(
        session, tool_type=tool_type, instance=instance
    )
    eff_duration = max(1, (remaining_s + 59) // 60)
    params = {
        "duration_minutes": eff_duration,
        "accuracy": float(inst_p.get("accuracy", cfg.accuracy)),
        "wideness_m": float(footprint.wideness_m),
        "cell_size_m": float(cell_size),
        "center_lat": float(footprint.center_lat),
        "center_lon": float(footprint.center_lon),
    }
    return _create_timed_row(
        session,
        user_id=user_id,
        instance_id=int(instance.id),
        action_key=ACTION_KEY_FORMATION_MAP,
        params=params,
        remaining_s=remaining_s,
    )


def start_timed_session(
    session: Session,
    *,
    user_id: int,
    tool_id: int,
    lat: float | None = None,
    lon: float | None = None,
) -> ToolSession:
    """Start a timed overlay session for the owned tool card.

    ``tool_id`` is the catalog tool_type id. Session length is remaining battery.
    Formation Map uses [lat]/[lon] for first placement.
    """
    selected = resolve_owned_tool_selection(session, user_id=user_id, tool_id=tool_id)
    if selected is None:
        tool_type = session.get(ToolType, tool_id)
        if tool_type is None:
            raise NotFoundError(f"Tool {tool_id} not found")
        # Validates the catalog tool is a known timed overlay.
        _action_key_for_tool_name(tool_type.name)
        raise ValidationError(f"You must own {tool_type.name} to use it")

    tool_type, instance = selected
    action_key = _action_key_for_tool_name(tool_type.name)

    if action_key == ACTION_KEY_FORMATION_MAP:
        return start_formation_session(
            session, user_id=user_id, tool_id=tool_id, lat=lat, lon=lon
        )

    ensure_exclusive_tool_session(
        session, user_id=user_id, instance_id=int(instance.id)
    )

    game = get_game_config()
    # Same as other timed tools: use whatever battery remains (no floor).
    remaining_s = allocate_remaining_for_start(
        session,
        tool_type=tool_type,
        instance=instance,
    )
    eff_duration = max(1, (remaining_s + 59) // 60)
    inst_p = instance.params_json or {}

    if is_guidance_action_key(action_key):
        kind = guidance_kind_for_tool_name(tool_type.name)
        cfg = guidance_config_for_action_key(action_key)
        params = _guidance_params(
            kind=kind, cfg=cfg, inst_p=inst_p, duration_minutes=eff_duration
        )
    elif action_key == ACTION_KEY_ORBIT_SURVEY:
        if tool_type.name != TOOL_NAME_ORBIT_SURVEY:
            raise ValidationError("This action is only available for Orbit Survey")
        cfg = game.tool_actions.orbit_survey
        params = _orbit_params(cfg=cfg, inst_p=inst_p, duration_minutes=eff_duration)
    elif action_key == ACTION_KEY_TERRAIN_ECHO:
        if tool_type.name != TOOL_NAME_TERRAIN_ECHO:
            raise ValidationError("This action is only available for Terrain Echo")
        cfg = game.tool_actions.terrain_echo
        params = _terrain_params(cfg=cfg, inst_p=inst_p, duration_minutes=eff_duration)
    elif action_key == ACTION_KEY_RIDGE_GLASS:
        if tool_type.name != TOOL_NAME_RIDGE_GLASS:
            raise ValidationError("This action is only available for Ridge Glass")
        cfg = game.tool_actions.ridge_glass
        params = _main_param_buff_params(
            cfg=cfg, inst_p=inst_p, duration_minutes=eff_duration
        )
    elif action_key == ACTION_KEY_EXPEDITION_DRIVETRAIN:
        if tool_type.name != TOOL_NAME_EXPEDITION_DRIVETRAIN:
            raise ValidationError(
                "This action is only available for Expedition Drivetrain"
            )
        cfg = game.tool_actions.expedition_drivetrain
        params = _main_param_buff_params(
            cfg=cfg, inst_p=inst_p, duration_minutes=eff_duration
        )
    else:
        raise ValidationError(f"Unsupported timed action_key: {action_key}")

    return _create_timed_row(
        session,
        user_id=user_id,
        instance_id=int(instance.id),
        action_key=action_key,
        params=params,
        remaining_s=remaining_s,
    )


def get_active_timed_session(
    session: Session,
    *,
    user_id: int,
    action_keys: tuple[str, ...] | list[str] | None = None,
) -> ToolSession | None:
    """Return the user's active timed session, optionally filtered by action_keys."""
    keys = tuple(action_keys) if action_keys is not None else TIMED_OVERLAY_ACTION_KEYS
    row = session.exec(
        select(ToolSession)
        .where(
            col(ToolSession.user_id) == user_id,
            col(ToolSession.action_key).in_(keys),
            col(ToolSession.status) == SESSION_STATUS_ACTIVE,
        )
        .order_by(col(ToolSession.started_at).desc())
    ).first()
    if row is None:
        return None
    row = expire_if_needed(session, row)
    if row.status != SESSION_STATUS_ACTIVE:
        return None
    return row


def cancel_timed_session(
    session: Session,
    *,
    user_id: int,
    session_id: int | None = None,
    action_keys: tuple[str, ...] | list[str] | None = None,
) -> ToolSession | None:
    """Cancel a specific timed session or the active one for [action_keys]."""
    keys = tuple(action_keys) if action_keys is not None else TIMED_OVERLAY_ACTION_KEYS

    if session_id is not None:
        row = session.get(ToolSession, session_id)
        if (
            row is None
            or int(row.user_id) != user_id
            or row.action_key not in keys
        ):
            raise NotFoundError(f"Timed session {session_id} not found")
        row = expire_if_needed(session, row)
        if row.status == SESSION_STATUS_ACTIVE:
            now = _utcnow()
            row.status = SESSION_STATUS_CANCELLED
            close_session(row, now=now, stop_reason=STOP_REASON_MANUAL)
            session.add(row)
            session.commit()
            session.refresh(row)
        return row

    row = get_active_timed_session(
        session, user_id=user_id, action_keys=keys
    )
    if row is None:
        return None
    now = _utcnow()
    row.status = SESSION_STATUS_CANCELLED
    close_session(row, now=now, stop_reason=STOP_REASON_MANUAL)
    session.add(row)
    session.commit()
    session.refresh(row)
    return row
