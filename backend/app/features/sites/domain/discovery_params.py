"""Resolve effective site-discovery params (baseline + level + weather + tool boosts)."""

from __future__ import annotations

from dataclasses import dataclass

from sqlmodel import Session

from app.core.game_config import get_game_config
from app.models.site import Site
from app.models.tool_session import GLOBAL_BUFF_ACTION_KEYS, GUIDANCE_ACTION_KEYS
from app.features.progression.public import (
    resolve_site_discovery_main_params,
    tool_mods_from_session_params,
)
from app.features.progression.public import get_skill_xp
from app.features.progression.public import level_for_xp
from app.shared.geography.geo_utils import haversine_km
from app.features.sites.application.nearby import list_discoverable_sites_in_radius
from app.features.weather.public import period_at


@dataclass(frozen=True)
class ResolvedSiteDiscoveryParams:
    visibility_distance_m: float
    discovery_chance: float  # effective (disguise-applied), clamped 0..1
    base_discovery_chance: float  # before rival disguise multiplier
    discover_site_xp: float
    discover_site_as_first_xp: float


def nearest_discoverable_site_id(
    session: Session,
    *,
    user_id: int,
    lat: float,
    lon: float,
) -> int | None:
    """Id of the nearest still-discoverable field site, or None."""
    radius_km = float(get_game_config().site_discovery.client.cache_radius_km)
    rows = list_discoverable_sites_in_radius(
        session,
        lat=lat,
        lon=lon,
        radius_km=radius_km,
        user_id=user_id,
    )
    best_id: int | None = None
    best_km = float("inf")
    for row in rows:
        site = row.site
        if site.latitude is None or site.longitude is None:
            continue
        dist = haversine_km(
            lat, lon, float(site.latitude), float(site.longitude)
        )
        if dist < best_km:
            best_km = dist
            best_id = int(site.site_id)
    return best_id


def _skill_level_for_user(session: Session, user_id: int) -> int:
    from app.models.user import User

    user = session.get(User, user_id)
    if user is None:
        return 1
    return level_for_xp(get_skill_xp(user, "field_survey"))


def resolve_site_discovery_params(
    session: Session,
    *,
    user_id: int,
    site: Site,
    lat: float | None = None,
    lon: float | None = None,
) -> ResolvedSiteDiscoveryParams:
    """Baseline main_params + level + weather_time; active tools may boost.

    Global buff tools (Ridge Glass, mobility tools, Nocturne Lens) apply
    ``modifies_main_params.using`` to every site while active. Period-gated
    buffs auto-stop when solar time leaves ``active_weather_times``. Guidance
    tools still replace discovery chance only for the nearest still-discoverable
    site.
    """
    # Lazy import: tool_session → site nearby → discover → this module.
    from app.features.tools.public import (
        get_active_timed_session,
    )
    from app.features.tools.public import (
        auto_stop_buff_if_period_left,
        buff_mods_allowed_for_period,
    )

    skill_level = _skill_level_for_user(session, user_id)
    tool_mods = None

    weather_time = None
    weather_type = None
    if lat is not None and lon is not None:
        weather_time = period_at(latitude=lat, longitude=lon)
        try:
            from app.features.weather.public import get_weather

            weather_type = get_weather(lat=lat, lon=lon).weather_type
        except Exception:
            weather_type = None

    buff = get_active_timed_session(
        session, user_id=user_id, action_keys=GLOBAL_BUFF_ACTION_KEYS
    )
    if buff is not None:
        closed = auto_stop_buff_if_period_left(
            session, buff, weather_time=weather_time
        )
        if closed is None and buff_mods_allowed_for_period(
            buff.params_json or {}, weather_time=weather_time
        ):
            buff_mods = tool_mods_from_session_params(
                buff.params_json or {},
                when="using",
                skill_id="field_survey",
            )
            if buff_mods:
                tool_mods = buff_mods
    elif lat is not None and lon is not None:
        guidance = get_active_timed_session(
            session, user_id=user_id, action_keys=GUIDANCE_ACTION_KEYS
        )
        params = (guidance.params_json if guidance is not None else None) or {}
        # Active session → apply `using` / site_discovery only.
        using_mods = tool_mods_from_session_params(
            params, when="using", skill_id="field_survey"
        )
        if guidance is not None and using_mods:
            nearest_id = nearest_discoverable_site_id(
                session,
                user_id=user_id,
                lat=lat,
                lon=lon,
            )
            if nearest_id is not None and int(site.site_id) == nearest_id:
                tool_mods = using_mods

    resolved = resolve_site_discovery_main_params(
        skill_level=skill_level,
        weather_time=weather_time,
        weather_type=weather_type,
        tool_mods=tool_mods,
    )
    base_chance = float(resolved["discovery_chance"])
    from app.features.tools.public import (
        rival_discovery_chance_multiplier,
    )

    mult = rival_discovery_chance_multiplier(
        session, site_id=int(site.site_id), rolling_user_id=user_id
    )
    discovery_chance = base_chance
    if mult != 1.0:
        discovery_chance = max(0.0, min(1.0, base_chance * mult))

    return ResolvedSiteDiscoveryParams(
        visibility_distance_m=float(resolved["visibility_distance_m"]),
        discovery_chance=discovery_chance,
        base_discovery_chance=base_chance,
        discover_site_xp=float(resolved["discover_site_xp"]),
        discover_site_as_first_xp=float(resolved["discover_site_as_first_xp"]),
    )
