"""Discover a field site (create user_site discoverer link)."""

from __future__ import annotations

from sqlmodel import Session, col, select

from app.core.exceptions import NotFoundError, ValidationError
from app.models.data_source import DATA_SOURCE_FIELD
from app.models.site import Site
from app.models.user_notification import UserNotification, UserNotificationType
from app.models.user_site import (
    SITE_STATUS_DISCOVERED,
    SITE_STATUS_HIDDEN,
    USER_SITE_ROLE_DISCOVERER,
    UserSite,
)
from app.services.push_service import send_site_discovered_push
from app.services.site_service.geo_utils import haversine_km
from app.services.site_service.list import get_site_by_id
from app.services.site_service.summary import SiteRow

DISCOVER_MAX_DISTANCE_M = 500.0
_DISCOVER_MAX_DISTANCE_KM = DISCOVER_MAX_DISTANCE_M / 1000.0


def _site_label(site: Site) -> str:
    formation = (site.formation or "").strip()
    if formation:
        return formation
    return f"Site #{site.site_id}"


def discover_site(
    session: Session,
    *,
    site_id: int,
    user_id: int,
    lat: float,
    lon: float,
) -> SiteRow:
    """Link the user as discoverer when within range and status allows it."""
    site = session.get(Site, site_id)
    if site is None or site.data_source != DATA_SOURCE_FIELD:
        raise NotFoundError(f"Field site {site_id} not found")
    if site.latitude is None or site.longitude is None:
        raise ValidationError("Site has no coordinates")

    distance_km = haversine_km(
        lat, lon, float(site.latitude), float(site.longitude)
    )
    if distance_km > _DISCOVER_MAX_DISTANCE_KM:
        raise ValidationError(
            f"Must be within {int(DISCOVER_MAX_DISTANCE_M)} m of the site to discover it"
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
    if existing is None:
        session.add(
            UserSite(
                user_id=user_id,
                site_id=site_id,
                role=USER_SITE_ROLE_DISCOVERER,
            )
        )
        notification = UserNotification(
            user_id=user_id,
            type=UserNotificationType.SITE_DISCOVERED,
            site_id=site_id,
        )
        session.add(notification)
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

    return get_site_by_id(session, site_id, data_source=DATA_SOURCE_FIELD)
