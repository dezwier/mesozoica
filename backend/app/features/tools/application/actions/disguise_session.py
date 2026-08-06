"""Site-stewardship disguise covers (Brush Scrim / Blackout Cover)."""

from __future__ import annotations

import random
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Literal

from sqlmodel import Session, col, select

from app.core.exceptions import NotFoundError, ValidationError
from app.core.game_config import get_game_config
from app.shared.data_sources import DATA_SOURCE_FIELD
from app.models.site import Site
from app.models.tool_session import (
    ACTION_KEY_BLACKOUT_COVER,
    ACTION_KEY_BRUSH_SCRIM,
    DISGUISE_ACTION_KEYS,
    LIVE_STATUSES,
    SESSION_STATUS_ACTIVE,
    SESSION_STATUS_CANCELLED,
    STOP_REASON_MANUAL,
    ToolSession,
)
from app.models.tool_type import ToolType
from app.models.user import User
from app.models.user_site import (
    STATUS_ROLES,
    USER_SITE_ROLE_DISCOVERER,
    USER_SITE_ROLE_DISGUISER,
    UserSite,
)
from app.features.progression.public import award_disguise_of_site_xp
from app.features.progression.public import (
    resolve_site_stewardship_main_params,
    tool_mods_from_session_params,
)
from app.features.progression.public import get_skill_xp
from app.features.progression.public import level_for_xp
from app.features.tools.application.actions.tool_session.lifecycle import (
    close_session,
    expire_if_needed,
)
from app.features.tools.application.catalog.collect import resolve_owned_tool_selection

TOOL_NAME_BRUSH_SCRIM = "Brush Scrim"
TOOL_NAME_BLACKOUT_COVER = "Blackout Cover"

_TOOL_NAME_TO_ACTION = {
    TOOL_NAME_BRUSH_SCRIM: ACTION_KEY_BRUSH_SCRIM,
    TOOL_NAME_BLACKOUT_COVER: ACTION_KEY_BLACKOUT_COVER,
}


def is_disguise_tool_name(name: str) -> bool:
    return name in _TOOL_NAME_TO_ACTION


def action_key_for_disguise_tool_name(name: str) -> str:
    try:
        return _TOOL_NAME_TO_ACTION[name]
    except KeyError as exc:
        raise ValidationError(f"Unknown disguise tool: {name}") from exc


def _utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


@dataclass(frozen=True)
class ActiveDisguise:
    """One active cover on a site that affects rival discovery."""

    user_id: int
    site_id: int
    session_id: int
    rival_discovery_chance: float
    params_json: dict


def clear_disguiser_link_for_session(session: Session, row: ToolSession) -> None:
    """Remove the disguiser user_site row tied to this session, if any."""
    if row.action_key not in DISGUISE_ACTION_KEYS:
        return
    site_id = (row.state_json or {}).get("site_id")
    if site_id is None:
        return
    links = list(
        session.exec(
            select(UserSite).where(
                col(UserSite.user_id) == int(row.user_id),
                col(UserSite.site_id) == int(site_id),
                col(UserSite.role) == USER_SITE_ROLE_DISGUISER,
            )
        ).all()
    )
    for link in links:
        if (
            link.source_session_id is None
            or int(link.source_session_id) == int(row.id)
        ):
            session.delete(link)


def cancel_active_disguise_sessions(
    session: Session,
    *,
    user_id: int,
) -> None:
    """Stop any live disguise sessions for the user and clear disguiser links."""
    now = _utcnow()
    rows = list(
        session.exec(
            select(ToolSession).where(
                col(ToolSession.user_id) == user_id,
                col(ToolSession.action_key).in_(DISGUISE_ACTION_KEYS),
                col(ToolSession.status).in_(LIVE_STATUSES),
            )
        ).all()
    )
    for row in rows:
        refreshed = expire_if_needed(session, row)
        if refreshed.status not in LIVE_STATUSES:
            continue
        clear_disguiser_link_for_session(session, refreshed)
        refreshed.status = SESSION_STATUS_CANCELLED
        close_session(refreshed, now=now, stop_reason=STOP_REASON_MANUAL)
        session.add(refreshed)
    if rows:
        session.commit()


def _require_discoverer(session: Session, *, user_id: int, site_id: int) -> Site:
    site = session.get(Site, site_id)
    if site is None or site.data_source != DATA_SOURCE_FIELD:
        raise NotFoundError(f"Field site {site_id} not found")
    discoverer = session.exec(
        select(UserSite).where(
            col(UserSite.user_id) == user_id,
            col(UserSite.site_id) == site_id,
            col(UserSite.role) == USER_SITE_ROLE_DISCOVERER,
        )
    ).first()
    if discoverer is None:
        raise ValidationError(
            "You must discover a site before you can disguise it"
        )
    return site


def prepare_disguise_start(
    session: Session,
    *,
    user_id: int,
    tool_id: int,
    site_id: int,
) -> tuple[ToolType, object, str, dict]:
    """Validate ownership + discoverer; cancel prior disguise; return start knobs.

    Returns (tool_type, instance, action_key, params_snapshot) after
    ``cancel_active_disguise_sessions``. Caller must still call
    ``ensure_exclusive_tool_session`` and create the timed row, then
    ``attach_disguiser_link``.
    """
    selected = resolve_owned_tool_selection(
        session, user_id=user_id, tool_id=tool_id
    )
    if selected is None:
        tool_type = session.get(ToolType, tool_id)
        if tool_type is None:
            raise NotFoundError(f"Tool {tool_id} not found")
        if not is_disguise_tool_name(tool_type.name):
            raise ValidationError(
                "This action is only available for Brush Scrim or Blackout Cover"
            )
        raise ValidationError(f"You must own {tool_type.name} to use it")

    tool_type, instance = selected
    if not is_disguise_tool_name(tool_type.name):
        raise ValidationError(
            "This action is only available for Brush Scrim or Blackout Cover"
        )

    _require_discoverer(session, user_id=user_id, site_id=site_id)

    cancel_active_disguise_sessions(session, user_id=user_id)

    action_key = action_key_for_disguise_tool_name(tool_type.name)
    cfg = get_game_config().tool_actions.disguise_config_for(action_key)
    inst_p = instance.params_json or {}
    raw_mods = inst_p.get("modifies_main_params")
    if raw_mods is None and cfg.modifies_main_params is not None:
        raw_mods = cfg.modifies_main_params.model_dump(mode="json")
    params: dict = {
        "stats_explanation": inst_p.get(
            "stats_explanation", cfg.stats_explanation
        ),
    }
    if raw_mods is not None:
        params["modifies_main_params"] = raw_mods
    elif inst_p.get("discovery_chance_multiplier") is not None:
        # Legacy instance knobs still accepted until catalogs are re-seeded.
        params["modifies_main_params"] = {
            "using": {
                "field_survey": {
                    "rival_discovery_chance": {
                        "op": "multiply",
                        "value": float(inst_p["discovery_chance_multiplier"]),
                    }
                }
            }
        }
    return tool_type, instance, action_key, params


def attach_disguiser_link(
    session: Session,
    *,
    user_id: int,
    site_id: int,
    tool_session: ToolSession,
) -> None:
    """Create/replace the disguiser user_site row for this session."""
    existing = list(
        session.exec(
            select(UserSite).where(
                col(UserSite.user_id) == user_id,
                col(UserSite.role) == USER_SITE_ROLE_DISGUISER,
            )
        ).all()
    )
    for link in existing:
        session.delete(link)

    session.add(
        UserSite(
            user_id=user_id,
            site_id=site_id,
            role=USER_SITE_ROLE_DISGUISER,
            source_session_id=int(tool_session.id)
            if tool_session.id is not None
            else None,
        )
    )
    state = dict(tool_session.state_json or {})
    state["site_id"] = int(site_id)
    tool_session.state_json = state
    session.add(tool_session)
    session.commit()
    session.refresh(tool_session)


def list_active_disguises_for_site(
    session: Session,
    *,
    site_id: int,
) -> list[ActiveDisguise]:
    """Active disguiser covers on ``site_id`` (expired sessions are cleaned)."""
    links = list(
        session.exec(
            select(UserSite).where(
                col(UserSite.site_id) == site_id,
                col(UserSite.role) == USER_SITE_ROLE_DISGUISER,
            )
        ).all()
    )
    out: list[ActiveDisguise] = []
    for link in links:
        if link.source_session_id is None:
            session.delete(link)
            continue
        row = session.get(ToolSession, int(link.source_session_id))
        if row is None:
            session.delete(link)
            continue
        row = expire_if_needed(session, row)
        if row.status != SESSION_STATUS_ACTIVE:
            clear_disguiser_link_for_session(session, row)
            session.commit()
            continue
        params = dict(row.params_json or {})
        out.append(
            ActiveDisguise(
                user_id=int(link.user_id),
                site_id=int(site_id),
                session_id=int(row.id),
                rival_discovery_chance=_resolve_cover_rival_discovery(
                    session, user_id=int(link.user_id), params=params
                ),
                params_json=params,
            )
        )
    return out


def _stewardship_skill_level(session: Session, user_id: int) -> int:
    user = session.get(User, user_id)
    if user is None:
        return 1
    return level_for_xp(get_skill_xp(user, "field_survey"))


def _resolve_cover_rival_discovery(
    session: Session,
    *,
    user_id: int,
    params: dict,
) -> float:
    """Effective ``rival_discovery_chance`` for one active cover session."""
    tool_mods = tool_mods_from_session_params(
        params, when="using", skill_id="field_survey"
    )
    # Legacy snapshot: bare discovery_chance_multiplier.
    if (
        "rival_discovery_chance" not in tool_mods
        and params.get("discovery_chance_multiplier") is not None
    ):
        from app.core.game_config import ParamModifier

        tool_mods = {
            **tool_mods,
            "rival_discovery_chance": ParamModifier(
                op="multiply",
                value=float(params["discovery_chance_multiplier"]),
            ),
        }
    resolved = resolve_site_stewardship_main_params(
        skill_level=_stewardship_skill_level(session, user_id),
        tool_mods=tool_mods,
    )
    return max(0.0, float(resolved["rival_discovery_chance"]))


def _resolve_skill_rival_discovery(session: Session, *, user_id: int) -> float:
    """Skill-only ``rival_discovery_chance`` for a steward (no tool cover)."""
    resolved = resolve_site_stewardship_main_params(
        skill_level=_stewardship_skill_level(session, user_id),
    )
    return max(0.0, float(resolved["rival_discovery_chance"]))


def _user_has_status_above_hidden(
    session: Session, *, user_id: int, site_id: int
) -> bool:
    """True when the user has any site status role (not hidden)."""
    return (
        session.exec(
            select(UserSite.id).where(
                col(UserSite.user_id) == user_id,
                col(UserSite.site_id) == site_id,
                col(UserSite.role).in_(STATUS_ROLES),
            )
        ).first()
        is not None
    )


def rival_discovery_multiplier(
    session: Session,
    *,
    site_id: int,
    rolling_user_id: int,
) -> float:
    """Effective ``rival_discovery_chance`` for ``rolling_user_id`` on ``site_id``.

    Users with any status above hidden on the site are unaffected (1.0).
    Otherwise returns the strongest (minimum) resolved ``rival_discovery_chance``
    from active rival covers (skill + tool) and other users with status above
    hidden (skill only). Default 1.0 when nobody has claimed the site.
    """
    if _user_has_status_above_hidden(
        session, user_id=rolling_user_id, site_id=site_id
    ):
        return 1.0

    disguises = list_active_disguises_for_site(session, site_id=site_id)
    others = [d for d in disguises if d.user_id != rolling_user_id]
    values = [d.rival_discovery_chance for d in others]
    covered_user_ids = {d.user_id for d in others}

    steward_ids = session.exec(
        select(UserSite.user_id)
        .where(
            col(UserSite.site_id) == site_id,
            col(UserSite.role).in_(STATUS_ROLES),
            col(UserSite.user_id) != rolling_user_id,
        )
        .distinct()
    ).all()
    for steward_id in steward_ids:
        uid = int(steward_id)
        if uid in covered_user_ids:
            continue
        values.append(_resolve_skill_rival_discovery(session, user_id=uid))

    if not values:
        return 1.0
    return max(0.0, min(values))


# Back-compat alias.
rival_discovery_chance_multiplier = rival_discovery_multiplier


DisguiseDiscoveryRoll = Literal["hit", "blocked", "miss"]


def roll_discovery_with_disguise(
    session: Session,
    *,
    site_id: int,
    rolling_user_id: int,
    base_chance: float,
    rng: random.Random | None = None,
) -> DisguiseDiscoveryRoll:
    """Single Uniform roll against base chance, reduced by rival_discovery_chance.

    - ``hit``: roll clears the disguised (effective) chance → rival discovers.
    - ``blocked``: roll would have cleared base chance, but disguise stopped it
      (including Brush Scrim at ×0). Awards stewardship XP to disguisers.
    - ``miss``: roll misses even the undisguised base chance.
    """
    base = max(0.0, min(1.0, float(base_chance)))
    mult = rival_discovery_multiplier(
        session, site_id=site_id, rolling_user_id=rolling_user_id
    )
    effective = max(0.0, min(1.0, base * mult))
    roller = rng if rng is not None else random
    u = float(roller.random())
    if u < effective:
        return "hit"
    if mult < 1.0 and u < base:
        award_disguise_xp_on_rival_blocked(
            session, site_id=site_id, rolling_user_id=rolling_user_id
        )
        return "blocked"
    return "miss"


def award_disguise_xp_on_rival_blocked(
    session: Session,
    *,
    site_id: int,
    rolling_user_id: int,
) -> int:
    """Award site_stewardship XP when a disguise blocks a would-be discovery."""
    disguises = list_active_disguises_for_site(session, site_id=site_id)
    total = 0
    for cover in disguises:
        if cover.user_id == rolling_user_id:
            continue
        user = session.get(User, cover.user_id)
        if user is None:
            continue
        total += award_disguise_of_site_xp(user)
        session.add(user)
    return total


# Back-compat alias used by older call sites / tests.
award_disguise_xp_on_rival_discover = award_disguise_xp_on_rival_blocked
