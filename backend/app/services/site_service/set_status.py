"""Set field site status via user_site role (or clear for hidden)."""

from __future__ import annotations

from datetime import datetime, timezone

from sqlmodel import Session, col, select

from app.core.exceptions import NotFoundError, ValidationError
from app.models.data_source import DATA_SOURCE_FIELD
from app.models.site import Site
from app.models.user_notification import UserNotification, UserNotificationType
from app.models.user_site import (
    ROLE_TO_STATUS,
    SITE_STATUS_DISCOVERED,
    SITE_STATUS_HIDDEN,
    SITE_STATUSES,
    USER_SITE_ROLE_DISCOVERER,
    UserSite,
)
from app.services.push_service import send_site_discovered_push
from app.services.site_service.discover import DISCOVER_MAX_DISTANCE_M, _site_label
from app.services.site_service.geo_utils import haversine_km
from app.services.site_service.list import get_site_by_id
from app.services.site_service.summary import SiteRow

_STATUS_TO_ROLE: dict[str, str] = {
    status: role for role, status in ROLE_TO_STATUS.items()
}
_SET_STATUS_MAX_DISTANCE_KM = DISCOVER_MAX_DISTANCE_M / 1000.0


def set_site_status(
    session: Session,
    *,
    site_id: int,
    user_id: int,
    status: str,
    lat: float | None = None,
    lon: float | None = None,
    skip_distance_check: bool = False,
) -> SiteRow:
    """Set the site's latest status for the acting user.

    ``hidden`` clears all ``user_site`` rows for the site.
    Other statuses upsert the matching role with a fresh timestamp.
    Transitioning ``hidden`` → ``discovered`` creates inbox + FCM like discover.

    When ``skip_distance_check`` is True (admin), proximity is not enforced and
    ``lat``/``lon`` are optional for non-hidden statuses.
    """
    normalized = (status or "").strip().lower()
    if normalized not in SITE_STATUSES:
        raise ValidationError(
            f"status must be one of: {', '.join(SITE_STATUSES)}"
        )

    site = session.get(Site, site_id)
    if site is None or site.data_source != DATA_SOURCE_FIELD:
        raise NotFoundError(f"Field site {site_id} not found")

    before = get_site_by_id(session, site_id, data_source=DATA_SOURCE_FIELD)
    previous_status = before.status or SITE_STATUS_HIDDEN

    if normalized == SITE_STATUS_HIDDEN:
        rows = session.exec(
            select(UserSite).where(col(UserSite.site_id) == site_id)
        ).all()
        for row in rows:
            session.delete(row)
        session.commit()
        return get_site_by_id(session, site_id, data_source=DATA_SOURCE_FIELD)

    if site.latitude is None or site.longitude is None:
        raise ValidationError("Site has no coordinates")
    if not skip_distance_check:
        if lat is None or lon is None:
            raise ValidationError("lat and lon are required to set this status")
        distance_km = haversine_km(
            lat, lon, float(site.latitude), float(site.longitude)
        )
        if distance_km > _SET_STATUS_MAX_DISTANCE_KM:
            raise ValidationError(
                f"Must be within {int(DISCOVER_MAX_DISTANCE_M)} m of the site "
                f"to set status to {normalized}"
            )

    role = _STATUS_TO_ROLE[normalized]
    now = datetime.now(timezone.utc)
    existing = session.exec(
        select(UserSite).where(
            col(UserSite.user_id) == user_id,
            col(UserSite.site_id) == site_id,
            col(UserSite.role) == role,
        )
    ).first()
    if existing is None:
        session.add(
            UserSite(
                user_id=user_id,
                site_id=site_id,
                role=role,
                timestamp=now,
            )
        )
    else:
        existing.timestamp = now
        session.add(existing)

    should_notify = (
        previous_status == SITE_STATUS_HIDDEN
        and normalized == SITE_STATUS_DISCOVERED
        and role == USER_SITE_ROLE_DISCOVERER
    )
    if should_notify:
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

    session.commit()
    return get_site_by_id(session, site_id, data_source=DATA_SOURCE_FIELD)
