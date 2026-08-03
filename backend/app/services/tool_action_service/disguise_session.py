"""Site-stewardship disguise covers (Brush Scrim / Blackout Cover)."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone

from sqlmodel import Session, col, select

from app.core.exceptions import NotFoundError, ValidationError
from app.core.game_config import get_game_config
from app.models.data_source import DATA_SOURCE_FIELD
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
    USER_SITE_ROLE_DISCOVERER,
    USER_SITE_ROLE_DISGUISER,
    UserSite,
)
from app.services.level_service import award_skill_xp
from app.services.tool_action_service.tool_session.lifecycle import (
    close_session,
    expire_if_needed,
)
from app.services.tool_service.collect import resolve_owned_tool_selection

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
    discovery_chance_multiplier: float
    xp: int


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
    multiplier = float(
        inst_p.get(
            "discovery_chance_multiplier",
            cfg.discovery_chance_multiplier,
        )
    )
    xp = int(inst_p.get("xp", cfg.xp))
    params = {
        "discovery_chance_multiplier": max(0.0, min(1.0, multiplier)),
        "xp": max(0, xp),
        "stats_explanation": inst_p.get(
            "stats_explanation", cfg.stats_explanation
        ),
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
        params = row.params_json or {}
        out.append(
            ActiveDisguise(
                user_id=int(link.user_id),
                site_id=int(site_id),
                session_id=int(row.id),
                discovery_chance_multiplier=float(
                    params.get("discovery_chance_multiplier", 1.0)
                ),
                xp=max(0, int(params.get("xp", 0))),
            )
        )
    return out


def rival_discovery_chance_multiplier(
    session: Session,
    *,
    site_id: int,
    rolling_user_id: int,
) -> float:
    """Strongest (minimum) disguise multiplier for a non-discoverer, else 1.0."""
    has_discoverer = (
        session.exec(
            select(UserSite).where(
                col(UserSite.user_id) == rolling_user_id,
                col(UserSite.site_id) == site_id,
                col(UserSite.role) == USER_SITE_ROLE_DISCOVERER,
            )
        ).first()
        is not None
    )
    if has_discoverer:
        return 1.0

    disguises = list_active_disguises_for_site(session, site_id=site_id)
    if not disguises:
        return 1.0
    others = [d for d in disguises if d.user_id != rolling_user_id]
    if not others:
        return 1.0
    return min(d.discovery_chance_multiplier for d in others)


def award_disguise_xp_on_rival_discover(
    session: Session,
    *,
    site_id: int,
    discovering_user_id: int,
) -> int:
    """Award site_stewardship XP to each active disguiser. Returns total XP."""
    disguises = list_active_disguises_for_site(session, site_id=site_id)
    total = 0
    for cover in disguises:
        if cover.user_id == discovering_user_id:
            continue
        if cover.xp <= 0:
            continue
        user = session.get(User, cover.user_id)
        if user is None:
            continue
        total += award_skill_xp(
            user,
            "site_stewardship",
            amount=cover.xp,
            breakdown_delta={"disguise": cover.xp},
        )
        session.add(user)
    return total
