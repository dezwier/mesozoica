"""Links a user to an auth provider."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Optional

from sqlalchemy import UniqueConstraint
from sqlmodel import Field, SQLModel


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


class UserAuthIdentity(SQLModel, table=True):
    __tablename__ = "user_auth_identity"
    __table_args__ = (
        UniqueConstraint(
            "provider",
            "provider_user_id",
            name="uq_user_auth_identity_provider_provider_user_id",
        ),
    )

    id: Optional[int] = Field(default=None, primary_key=True)
    user_id: int = Field(foreign_key="user.id", index=True)
    provider: str = Field(index=True, max_length=32)
    provider_user_id: str = Field(index=True, max_length=255)
    email: Optional[str] = Field(default=None, max_length=255)
    created_at: datetime = Field(default_factory=_utc_now)
