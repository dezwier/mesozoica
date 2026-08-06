"""FCM (or other push) device tokens per user. Owned by the accounts feature."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Optional

from sqlmodel import Field, SQLModel


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


class UserDeviceToken(SQLModel, table=True):
    """Stores push device tokens for a user (e.g. FCM)."""

    __tablename__ = "user_device_token"

    id: Optional[int] = Field(default=None, primary_key=True)
    user_id: int = Field(foreign_key="user.id", index=True)
    token: str = Field(index=True, unique=True, max_length=512)
    platform: str = Field(default="android", max_length=16)
    created_at: datetime = Field(default_factory=_utc_now)
    last_used_at: Optional[datetime] = Field(default=None)
