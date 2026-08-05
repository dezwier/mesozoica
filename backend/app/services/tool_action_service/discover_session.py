"""Discover a field site from an aerial tool session."""

from __future__ import annotations

import random

from sqlmodel import Session, col, select

from app.core.exceptions import NotFoundError, ValidationError
from app.models.data_source import DATA_SOURCE_FIELD
from app.models.site import (
    HOW_DISCOVERED_AERIAL_RECON,
    HOW_DISCOVERED_VALUES,
    Site,
)
from app.models.user_notification import UserNotification, UserNotificationType
from app.models.user_site import (
    SITE_STATUS_DISCOVERED,
    SITE_STATUS_HIDDEN,
    USER_SITE_ROLE_DISCOVERER,
    UserSite,
)
from app.services.push_service import send_site_discovered_push
from app.services.field_service.field_coordinate_enrich import (
    apply_site_discovery_enrichment,
)
from app.services.field_service.field_fossil_onboard import (
    DiscoverFossilOnboardResult,
    ensure_fossils_on_site_discovery,
)
from app.services.site_common.geo_utils import haversine_km
from app.services.site_common.labels import site_display_title
from app.services.site_service.list import get_site_by_id


def discover_site_from_aerial(
    session: Session,
    *,
    site_id: int,
    user_id: int,
    lat: float,
    lon: float,
    max_distance_m: float,
    discovery_chance: float,
    how_discovered: str = HOW_DISCOVERED_AERIAL_RECON,
    session_id: int | None = None,
    rng: random.Random | None = None,
) -> DiscoverFossilOnboardResult | None:
    """Link discoverer using craft position. Returns None on chance miss.

    Does not raise on chance miss (session events record ``miss`` instead).
    """
    if how_discovered not in HOW_DISCOVERED_VALUES:
        raise ValidationError(f"Invalid how_discovered: {how_discovered}")

    site = session.get(Site, site_id)
    if site is None or site.data_source != DATA_SOURCE_FIELD:
        raise NotFoundError(f"Field site {site_id} not found")
    if site.latitude is None or site.longitude is None:
        raise ValidationError("Site has no coordinates")

    distance_km = haversine_km(
        lat, lon, float(site.latitude), float(site.longitude)
    )
    if distance_km > max_distance_m / 1000.0:
        raise ValidationError(
            f"Craft must be within {int(max_distance_m)} m of the site"
        )

    row = get_site_by_id(session, site_id, data_source=DATA_SOURCE_FIELD)
    current_status = row.status or SITE_STATUS_HIDDEN
    if current_status not in (SITE_STATUS_HIDDEN, SITE_STATUS_DISCOVERED):
        raise ValidationError(
            f"Site cannot be discovered while status is {current_status}"
        )

    existing = session.exec(
        select(UserSite).where(
            col(UserSite.user_id) == user_id,
            col(UserSite.site_id) == site_id,
            col(UserSite.role) == USER_SITE_ROLE_DISCOVERER,
        )
    ).first()
    if existing is not None:
        return ensure_fossils_on_site_discovery(
            session, site_id=site_id, user_id=user_id
        )

    roller = rng if rng is not None else random
    from app.services.tool_action_service.disguise_session import (
        roll_discovery_with_disguise,
    )

    outcome = roll_discovery_with_disguise(
        session,
        site_id=site_id,
        rolling_user_id=user_id,
        base_chance=float(discovery_chance),
        rng=roller,
    )
    if outcome != "hit":
        return None

    prior_discoverer = session.exec(
        select(UserSite).where(
            col(UserSite.site_id) == site_id,
            col(UserSite.role) == USER_SITE_ROLE_DISCOVERER,
        )
    ).first()
    # Source of truth for firstness is live discoverer rows, not site.how_discovered.
    is_discover_site_as_first = prior_discoverer is None
    session.add(
        UserSite(
            user_id=user_id,
            site_id=site_id,
            role=USER_SITE_ROLE_DISCOVERER,
            source_session_id=session_id,
            was_first=is_discover_site_as_first,
        )
    )
    apply_site_discovery_enrichment(
        session, site, how_discovered=how_discovered
    )
    notification = UserNotification(
        user_id=user_id,
        type=UserNotificationType.SITE_DISCOVERED,
        site_id=site_id,
    )
    session.add(notification)

    from app.models.user import User
    from app.services.level_service import (
        award_discover_site_as_first_xp,
        award_site_discover_xp,
    )
    from app.services.weather_service.solar import period_at

    user = session.get(User, user_id)
    if user is not None:
        weather_time = period_at(latitude=lat, longitude=lon)
        weather_type = None
        try:
            from app.services.weather_service import get_weather

            weather_type = get_weather(lat=lat, lon=lon).weather_type
        except Exception:
            weather_type = None
        award_site_discover_xp(
            user, weather_time=weather_time, weather_type=weather_type
        )
        if is_discover_site_as_first:
            award_discover_site_as_first_xp(
                user, weather_time=weather_time, weather_type=weather_type
            )
        session.add(user)

    session.commit()
    session.refresh(notification)
    if notification.id is not None:
        send_site_discovered_push(
            session,
            user_id=user_id,
            site_id=site_id,
            notification_id=notification.id,
            site_label=site_display_title(site),
        )

    return ensure_fossils_on_site_discovery(
        session, site_id=site_id, user_id=user_id
    )
