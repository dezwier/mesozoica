"""Notification schemas. Owned by the accounts feature."""

from __future__ import annotations

from datetime import datetime
from typing import Optional

from pydantic import BaseModel


class UserNotificationResponse(BaseModel):
    """Single user notification."""

    id: int
    type: str
    actor_user_id: Optional[int] = None
    actor_username: str = ""
    site_id: Optional[int] = None
    site_label: str = ""
    read: bool
    created_at: datetime

    class Config:
        from_attributes = True


class UserNotificationsResponse(BaseModel):
    """List of user notifications."""

    notifications: list[UserNotificationResponse]
