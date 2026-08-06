"""User notifications endpoint. Owned by the accounts feature."""

from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, HTTPException, status
from sqlmodel import Session, select

from app.core.database import get_session
from app.core.security import get_current_user
from app.models.user import User
from app.models.user_notification import UserNotification
from app.schemas.common import OkResponse
from app.schemas.notification import UserNotificationsResponse
from app.features.accounts.application.notification_enrichment import notifications_to_response

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/notifications", tags=["notifications"])


@router.get("", response_model=UserNotificationsResponse)
async def get_notifications(
    current_user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """List current user's notifications."""
    notifications = session.exec(
        select(UserNotification)
        .where(UserNotification.user_id == current_user.id)
        .order_by(UserNotification.created_at.desc())  # type: ignore[attr-defined]
    ).all()
    result = notifications_to_response(session, list(notifications))
    return UserNotificationsResponse(notifications=result)


@router.patch("/{notification_id}/read", response_model=OkResponse)
async def mark_notification_read(
    notification_id: int,
    current_user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """Mark a notification as read."""
    notification = session.get(UserNotification, notification_id)
    if not notification:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Notification not found",
        )
    if notification.user_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not your notification",
        )
    notification.read = True
    session.add(notification)
    session.commit()

    # Keep the OS app-icon badge aligned with remaining unread notifications.
    from app.features.accounts.infrastructure.push import sync_unread_badge

    try:
        sync_unread_badge(session, current_user.id)
    except Exception as exc:
        logger.warning("Failed to sync unread badge after mark-read: %s", exc)

    return OkResponse()
