"""Durable notification and push policy for gameplay celebrations."""

from __future__ import annotations

from dataclasses import dataclass
from sqlmodel import Session

from app.features.accounts.infrastructure.push import send_site_celebration_push
from app.features.accounts.models.user_notification import (
    UserNotification,
    UserNotificationType,
)


SITE_CELEBRATION_TYPES = frozenset(
    {
        UserNotificationType.SITE_DISCOVERED,
        UserNotificationType.SITE_IDENTIFIED,
        UserNotificationType.SITE_DOCUMENTED,
    }
)


@dataclass(frozen=True)
class CelebrationNotificationDescriptor:
    notification_id: int
    type: str
    site_id: int


def create_site_celebration_notification(
    session: Session,
    *,
    user_id: int,
    site_id: int,
    notification_type: str,
) -> UserNotification:
    """Stage one durable celebration notification in the caller's transaction."""
    if notification_type not in SITE_CELEBRATION_TYPES:
        raise ValueError(f"Unsupported site celebration type: {notification_type}")
    notification = UserNotification(
        user_id=user_id,
        type=notification_type,
        site_id=site_id,
    )
    session.add(notification)
    return notification


def deliver_site_celebration_notification(
    session: Session,
    notification: UserNotification,
    *,
    site_label: str,
) -> CelebrationNotificationDescriptor | None:
    """Dispatch push after the caller committed and return the client descriptor."""
    if notification.id is None or notification.site_id is None:
        return None
    descriptor = CelebrationNotificationDescriptor(
        notification_id=int(notification.id),
        type=notification.type,
        site_id=int(notification.site_id),
    )
    send_site_celebration_push(
        session,
        user_id=int(notification.user_id),
        site_id=descriptor.site_id,
        notification_id=descriptor.notification_id,
        notification_type=descriptor.type,
        site_label=site_label,
    )
    return descriptor
