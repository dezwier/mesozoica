"""Set field site status via user_site role (or clear for hidden)."""

from __future__ import annotations

from datetime import datetime, timezone

from sqlmodel import Session, col, select

from app.core.exceptions import NotFoundError, ValidationError
from app.shared.data_sources import DATA_SOURCE_FIELD
from app.models.site import (
    HOW_DISCOVERED_MANUAL,
    HOW_DISCOVERED_WALK,
    Site,
)
from app.models.user_notification import UserNotification, UserNotificationType
from app.models.user_site import (
    ROLE_TO_STATUS,
    SITE_STATUS_DISCOVERED,
    SITE_STATUS_HIDDEN,
    SITE_STATUS_IDENTIFIED,
    SITE_STATUSES,
    USER_SITE_ROLE_DISCOVERER,
    UserSite,
)
from app.features.accounts.public import send_site_discovered_push
from app.features.sites.application.discover import _site_label, discover_max_distance_m
from app.features.field.public import (
    apply_site_discovery_enrichment,
    DiscoverFossilOnboardResult,
    ensure_fossils_on_site_discovery,
)
from app.shared.geography.geo_utils import haversine_km
from app.features.sites.application.list import get_site_by_id
from app.features.sites.application.summary import SiteRow

_STATUS_TO_ROLE: dict[str, str] = {
    status: role for role, status in ROLE_TO_STATUS.items()
}


def set_site_status(
    session: Session,
    *,
    site_id: int,
    user_id: int,
    status: str,
    lat: float | None = None,
    lon: float | None = None,
    skip_distance_check: bool = False,
) -> SiteRow | DiscoverFossilOnboardResult:
    """Set the site's latest status for the acting user.

    ``hidden`` clears all ``user_site`` rows for the site.
    Other statuses upsert the matching role with a fresh timestamp.
    Transitioning ``hidden`` → ``discovered`` creates inbox + FCM like discover
    and returns fossil onboard metadata (same as ``discover_site``).

    When ``skip_distance_check`` is True (admin), proximity is not enforced and
    ``lat``/``lon`` are optional for non-hidden statuses.
    """
    normalized = (status or "").strip().lower()
    settable = tuple(s for s in SITE_STATUSES if s != SITE_STATUS_IDENTIFIED)
    if normalized not in settable:
        raise ValidationError(
            f"status must be one of: {', '.join(settable)}"
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
        # Allow a later discoverer to claim first-discovery again.
        if site.how_discovered is not None:
            site.how_discovered = None
            session.add(site)
        session.commit()
        return get_site_by_id(session, site_id, data_source=DATA_SOURCE_FIELD)

    if site.latitude is None or site.longitude is None:
        raise ValidationError("Site has no coordinates")
    if not skip_distance_check:
        if lat is None or lon is None:
            raise ValidationError("lat and lon are required to set this status")
        max_distance_m = discover_max_distance_m()
        distance_km = haversine_km(
            lat, lon, float(site.latitude), float(site.longitude)
        )
        if distance_km > max_distance_m / 1000.0:
            raise ValidationError(
                f"Must be within {int(max_distance_m)} m of the site "
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
    is_new_role = existing is None
    is_discover_site_as_first = False
    if is_new_role and role == USER_SITE_ROLE_DISCOVERER:
        prior_discoverer = session.exec(
            select(UserSite).where(
                col(UserSite.site_id) == site_id,
                col(UserSite.role) == USER_SITE_ROLE_DISCOVERER,
            )
        ).first()
        # Source of truth for firstness is live discoverer rows.
        is_discover_site_as_first = prior_discoverer is None
    if existing is None:
        session.add(
            UserSite(
                user_id=user_id,
                site_id=site_id,
                role=role,
                timestamp=now,
                was_first=is_discover_site_as_first,
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
    if should_notify or (
        normalized == SITE_STATUS_DISCOVERED and role == USER_SITE_ROLE_DISCOVERER
    ):
        how = (
            HOW_DISCOVERED_MANUAL
            if skip_distance_check
            else HOW_DISCOVERED_WALK
        )
        apply_site_discovery_enrichment(session, site, how_discovered=how)

    if is_new_role and role == USER_SITE_ROLE_DISCOVERER:
        from app.models.user import User
        from app.features.progression.public import (
            award_discover_site_as_first_xp,
            award_site_discover_xp,
        )

        user = session.get(User, user_id)
        if user is not None:
            award_site_discover_xp(user)
            if is_discover_site_as_first:
                award_discover_site_as_first_xp(user)
            session.add(user)

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
        return ensure_fossils_on_site_discovery(
            session, site_id=site_id, user_id=user_id
        )

    session.commit()
    if normalized == SITE_STATUS_DISCOVERED:
        return ensure_fossils_on_site_discovery(
            session, site_id=site_id, user_id=user_id
        )
    return get_site_by_id(session, site_id, data_source=DATA_SOURCE_FIELD)
