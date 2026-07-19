"""In-app user notifications (friend requests, site discovery)."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Optional

from sqlalchemy import Column, ForeignKey, Integer, String as SAString
from sqlmodel import Field, SQLModel


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


class UserNotificationType:
    """Notification type constants."""

    FRIEND_REQUEST_RECEIVED = "friend_request_received"
    FRIEND_REQUEST_ACCEPTED = "friend_request_accepted"
    SITE_DISCOVERED = "site_discovered"


class UserNotification(SQLModel, table=True):
    """Stored notification for a user."""

    __tablename__ = "user_notification"

    id: Optional[int] = Field(default=None, primary_key=True)
    user_id: int = Field(foreign_key="user.id")
    type: str = Field(sa_column=Column(SAString, nullable=False))
    actor_user_id: Optional[int] = Field(default=None, foreign_key="user.id")
    site_id: Optional[int] = Field(
        default=None,
        sa_column=Column(
            Integer,
            ForeignKey("site.site_id", ondelete="SET NULL"),
            nullable=True,
            index=True,
        ),
    )
    read: bool = Field(default=False)
    created_at: datetime = Field(default_factory=_utc_now)
