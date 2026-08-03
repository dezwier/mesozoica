"""Resolve effective site-discovery params (baseline + level + weather + tool boosts)."""

from __future__ import annotations

from dataclasses import dataclass

from sqlmodel import Session

from app.core.game_config import get_game_config
from app.models.site import Site
from app.models.tool_session import ACTION_KEY_RIDGE_GLASS, GUIDANCE_ACTION_KEYS
from app.services.level_service.main_params import (
    resolve_site_discovery_main_params,
    tool_mods_from_session_params,
)
from app.services.level_service.skills import get_skill_xp
from app.services.level_service.xp_table import level_for_xp
from app.services.site_common.geo_utils import haversine_km
from app.services.site_service.nearby import list_discoverable_sites_in_radius
from app.services.weather_service.solar import period_at


@dataclass(frozen=True)
class ResolvedSiteDiscoveryParams:
    visibility_distance_m: float
    discovery_chance: float  # clamped 0..1
    site_discovery_xp: float

    # Back-compat alias.
    @property
    def max_distance_m(self) -> float:
        return self.visibility_distance_m


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
    return level_for_xp(get_skill_xp(user, "site_discovery"))


def resolve_site_discovery_params(
    session: Session,
    *,
    user_id: int,
    site: Site,
    lat: float | None = None,
    lon: float | None = None,
) -> ResolvedSiteDiscoveryParams:
    """Baseline main_params + level + weather_time; active tools may boost.

    Ridge Glass ``modifies_main_params.using`` applies globally to every site
    while the session is active. Guidance tools still replace discovery chance
    only for the nearest still-discoverable site.
    """
    # Lazy import: tool_session → site nearby → discover → this module.
    from app.services.tool_action_service.tool_session import (
        get_active_timed_session,
    )

    skill_level = _skill_level_for_user(session, user_id)
    tool_mods = None

    ridge = get_active_timed_session(
        session, user_id=user_id, action_keys=(ACTION_KEY_RIDGE_GLASS,)
    )
    if ridge is not None:
        ridge_mods = tool_mods_from_session_params(
            ridge.params_json or {},
            when="using",
            skill_id="site_discovery",
        )
        if ridge_mods:
            tool_mods = ridge_mods
    elif lat is not None and lon is not None:
        guidance = get_active_timed_session(
            session, user_id=user_id, action_keys=GUIDANCE_ACTION_KEYS
        )
        params = (guidance.params_json if guidance is not None else None) or {}
        # Active session → apply `using` / site_discovery only.
        using_mods = tool_mods_from_session_params(
            params, when="using", skill_id="site_discovery"
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

    weather_time = None
    weather_type = None
    if lat is not None and lon is not None:
        weather_time = period_at(latitude=lat, longitude=lon)
        try:
            from app.services.weather_service import get_weather

            weather_type = get_weather(lat=lat, lon=lon).weather_type
        except Exception:
            weather_type = None

    resolved = resolve_site_discovery_main_params(
        skill_level=skill_level,
        weather_time=weather_time,
        weather_type=weather_type,
        tool_mods=tool_mods,
    )
    return ResolvedSiteDiscoveryParams(
        visibility_distance_m=float(resolved["visibility_distance_m"]),
        discovery_chance=float(resolved["discovery_chance"]),
        site_discovery_xp=float(resolved["site_discovery_xp"]),
    )
