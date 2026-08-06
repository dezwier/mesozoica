"""User-to-user relationship (friend request, friend, block). Owned by the accounts feature."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Optional

from sqlmodel import Field, SQLModel


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


class UserUser(SQLModel, table=True):
    __tablename__ = "user_user"

    id: Optional[int] = Field(default=None, primary_key=True)
    user_id1: int = Field(foreign_key="user.id", index=True)
    user_id2: int = Field(foreign_key="user.id", index=True)
    relationship_type: str = Field(max_length=32, index=True)
    action_user_id: int = Field(foreign_key="user.id")
    created_at: datetime = Field(default_factory=_utc_now)
    updated_at: datetime = Field(default_factory=_utc_now)
