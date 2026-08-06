"""Discover a field site (create user_site discoverer link) and onboard fossils."""

from __future__ import annotations

import random

from sqlmodel import Session, col, select

from app.core.exceptions import DiscoveryChanceMissError, NotFoundError, ValidationError
from app.shared.data_sources import DATA_SOURCE_FIELD
from app.models.site import HOW_DISCOVERED_WALK, Site
from app.models.user_notification import UserNotification, UserNotificationType
from app.models.user_site import (
    SITE_STATUS_DISCOVERED,
    SITE_STATUS_HIDDEN,
    USER_SITE_ROLE_DISCOVERER,
    UserSite,
)
from app.features.accounts.public import send_site_discovered_push
from app.features.sites.domain.discovery_params import resolve_site_discovery_params
from app.features.field.public import (
    apply_site_discovery_enrichment,
    DiscoverFossilOnboardResult,
    ensure_fossils_on_site_discovery,
)
from app.shared.geography.geo_utils import haversine_km
from app.features.sites.domain.labels import site_display_title
from app.features.sites.application.list import get_site_by_id


def discover_max_distance_m() -> float:
    """Server-side max distance (meters) to discover / change site status."""
    from app.core.game_config import get_game_config

    return get_game_config().site_discovery.discovery_distance_m


def _site_label(site: Site) -> str:
    return site_display_title(site)


def discover_site(
    session: Session,
    *,
    site_id: int,
    user_id: int,
    lat: float,
    lon: float,
    rng: random.Random | None = None,
) -> DiscoverFossilOnboardResult:
    """Link the user as discoverer when within range and the chance roll succeeds.

    Also ensures global field fossils for the site (once) and awards locate-in-situ
    XP for depth-0 fossils (without creating ``user_fossil`` collection links).
    """
    site = session.get(Site, site_id)
    if site is None or site.data_source != DATA_SOURCE_FIELD:
        raise NotFoundError(f"Field site {site_id} not found")
    if site.latitude is None or site.longitude is None:
        raise ValidationError("Site has no coordinates")

    params = resolve_site_discovery_params(
        session, user_id=user_id, site=site, lat=lat, lon=lon
    )
    distance_km = haversine_km(
        lat, lon, float(site.latitude), float(site.longitude)
    )
    if distance_km > params.max_distance_m / 1000.0:
        raise ValidationError(
            f"Must be within {int(params.max_distance_m)} m of the site to discover it"
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
        # Idempotent re-hit: still onboard fossils / locate XP if needed.
        return ensure_fossils_on_site_discovery(
            session, site_id=site_id, user_id=user_id
        )

    roller = rng if rng is not None else random
    from app.features.tools.public import (
        roll_discovery_with_disguise,
    )

    outcome = roll_discovery_with_disguise(
        session,
        site_id=site_id,
        rolling_user_id=user_id,
        base_chance=params.base_discovery_chance,
        rng=roller,
    )
    if outcome != "hit":
        if outcome == "blocked":
            # Persist disguise XP even though discovery itself missed.
            session.commit()
        raise DiscoveryChanceMissError(
            "Discovery chance miss - stay nearby or re-enter range to try again"
        )

    prior_discoverer = session.exec(
        select(UserSite).where(
            col(UserSite.site_id) == site_id,
            col(UserSite.role) == USER_SITE_ROLE_DISCOVERER,
        )
    ).first()
    # Source of truth for firstness is live discoverer rows, not site.how_discovered
    # (that column is only the denormalized discovery method for filters/UI).
    is_discover_site_as_first = prior_discoverer is None
    session.add(
        UserSite(
            user_id=user_id,
            site_id=site_id,
            role=USER_SITE_ROLE_DISCOVERER,
            was_first=is_discover_site_as_first,
        )
    )
    apply_site_discovery_enrichment(
        session, site, how_discovered=HOW_DISCOVERED_WALK
    )
    notification = UserNotification(
        user_id=user_id,
        type=UserNotificationType.SITE_DISCOVERED,
        site_id=site_id,
    )
    session.add(notification)

    from app.models.user import User
    from app.features.progression.public import (
        award_discover_site_as_first_xp,
        award_site_discover_xp,
    )

    user = session.get(User, user_id)
    if user is not None:
        award_site_discover_xp(user, amount=int(round(params.discover_site_xp)))
        if is_discover_site_as_first:
            award_discover_site_as_first_xp(
                user, amount=int(round(params.discover_site_as_first_xp))
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
            site_label=_site_label(site),
        )

    return ensure_fossils_on_site_discovery(
        session, site_id=site_id, user_id=user_id
    )
