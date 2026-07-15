"""In-app user notifications (friend requests)."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Optional

from sqlalchemy import Column, String as SAString
from sqlmodel import Field, SQLModel


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


class UserNotificationType:
    """Notification type constants."""

    FRIEND_REQUEST_RECEIVED = "friend_request_received"
    FRIEND_REQUEST_ACCEPTED = "friend_request_accepted"


class UserNotification(SQLModel, table=True):
    """Stored notification for a user."""

    __tablename__ = "user_notification"

    id: Optional[int] = Field(default=None, primary_key=True)
    user_id: int = Field(foreign_key="user.id")
    type: str = Field(sa_column=Column(SAString, nullable=False))
    actor_user_id: Optional[int] = Field(default=None, foreign_key="user.id")
    read: bool = Field(default=False)
    created_at: datetime = Field(default_factory=_utc_now)
