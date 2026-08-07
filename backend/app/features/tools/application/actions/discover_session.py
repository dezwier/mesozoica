"""Discover a field site from an aerial tool session."""

from __future__ import annotations

import random
from dataclasses import replace

from sqlmodel import Session, col, select

from app.core.exceptions import NotFoundError, ValidationError
from app.shared.data_sources import DATA_SOURCE_FIELD
from app.models.site import (
    HOW_DISCOVERED_AERIAL_RECON,
    HOW_DISCOVERED_VALUES,
    Site,
)
from app.models.user_notification import UserNotificationType
from app.models.user_site import (
    SITE_STATUS_DISCOVERED,
    SITE_STATUS_HIDDEN,
    USER_SITE_ROLE_DISCOVERER,
    UserSite,
)
from app.features.accounts.public import (
    create_site_celebration_notification,
    deliver_site_celebration_notification,
)
from app.features.field.public import (
    apply_site_discovery_enrichment,
)
from app.features.field.public import (
    DiscoverFossilOnboardResult,
    ensure_fossils_on_site_discovery,
)
from app.shared.geography.geo_utils import haversine_km
from app.features.sites.public import site_display_title
from app.features.sites.public import get_site_by_id


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
    from app.features.tools.application.actions.disguise_session import (
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
    notification = create_site_celebration_notification(
        session,
        user_id=user_id,
        site_id=site_id,
        notification_type=UserNotificationType.SITE_DISCOVERED,
    )

    from app.models.user import User
    from app.features.progression.public import (
        award_discover_site_as_first_xp,
        award_site_discover_xp,
    )
    from app.features.weather.public import period_at

    user = session.get(User, user_id)
    if user is not None:
        weather_time = period_at(latitude=lat, longitude=lon)
        weather_type = None
        try:
            from app.features.weather.public import get_weather

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
    celebration = deliver_site_celebration_notification(
        session,
        notification,
        site_label=site_display_title(site),
    )

    result = ensure_fossils_on_site_discovery(
        session, site_id=site_id, user_id=user_id
    )
    if isinstance(result, DiscoverFossilOnboardResult):
        return replace(result, celebration=celebration)
    return result
