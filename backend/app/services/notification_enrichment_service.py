"""Build notification API payloads from notification rows."""

from __future__ import annotations

from sqlmodel import Session, select

from app.models.site import Site
from app.models.user import User
from app.models.user_notification import UserNotification
from app.schemas.notification import UserNotificationResponse
from app.services.site_service.labels import site_display_title


def notifications_to_response(
    session: Session, notifications: list[UserNotification]
) -> list[UserNotificationResponse]:
    if not notifications:
        return []

    actor_ids = {n.actor_user_id for n in notifications if n.actor_user_id is not None}
    actors: dict[int, User] = {}
    if actor_ids:
        rows = session.exec(select(User).where(User.id.in_(actor_ids))).all()
        actors = {u.id: u for u in rows if u.id is not None}

    site_ids = {n.site_id for n in notifications if n.site_id is not None}
    sites: dict[int, Site] = {}
    if site_ids:
        site_rows = session.exec(select(Site).where(Site.site_id.in_(site_ids))).all()
        sites = {s.site_id: s for s in site_rows}

    result: list[UserNotificationResponse] = []
    for notification in notifications:
        actor = (
            actors.get(notification.actor_user_id)
            if notification.actor_user_id is not None
            else None
        )
        site = sites.get(notification.site_id) if notification.site_id is not None else None
        result.append(
            UserNotificationResponse(
                id=notification.id,  # type: ignore[arg-type]
                type=notification.type,
                actor_user_id=notification.actor_user_id,
                actor_username=actor.username if actor else "",
                site_id=notification.site_id,
                site_label=site_display_title(site),
                read=notification.read,
                created_at=notification.created_at,
            )
        )
    return result
