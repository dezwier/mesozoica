"""User–fossil relationship (collection roles; status derived from latest role)."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Optional

from sqlalchemy import Column, DateTime, ForeignKey, Integer, UniqueConstraint, text
from sqlmodel import Field, SQLModel

USER_FOSSIL_ROLE_DISCOVERER = "discoverer"

USER_FOSSIL_ROLES: tuple[str, ...] = (USER_FOSSIL_ROLE_DISCOVERER,)

FOSSIL_STATUS_HIDDEN = "hidden"
FOSSIL_STATUS_DISCOVERED = "discovered"

FOSSIL_STATUSES: tuple[str, ...] = (
    FOSSIL_STATUS_HIDDEN,
    FOSSIL_STATUS_DISCOVERED,
)

ROLE_TO_STATUS: dict[str, str] = {
    USER_FOSSIL_ROLE_DISCOVERER: FOSSIL_STATUS_DISCOVERED,
}


def role_to_status(role: str | None) -> str:
    """Map a user_fossil role to API status; missing role → hidden."""
    if role is None:
        return FOSSIL_STATUS_HIDDEN
    return ROLE_TO_STATUS.get(role, FOSSIL_STATUS_HIDDEN)


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


class UserFossil(SQLModel, table=True):
    """Links a user to a fossil with a role; latest role by timestamp = fossil status."""

    __tablename__ = "user_fossil"
    __table_args__ = (
        UniqueConstraint(
            "user_id",
            "fossil_id",
            "role",
            name="uq_user_fossil_user_fossil_role",
        ),
    )

    id: Optional[int] = Field(default=None, primary_key=True)
    user_id: int = Field(
        sa_column=Column(
            Integer,
            ForeignKey("user.id", ondelete="CASCADE"),
            nullable=False,
            index=True,
        ),
    )
    fossil_id: int = Field(
        sa_column=Column(
            Integer,
            ForeignKey("fossil.id", ondelete="CASCADE"),
            nullable=False,
            index=True,
        ),
    )
    role: str = Field(
        max_length=16,
        description="discoverer (extend as gameplay roles grow)",
    )
    timestamp: datetime = Field(
        default_factory=_utc_now,
        sa_column=Column(
            DateTime(timezone=True),
            nullable=False,
            server_default=text("CURRENT_TIMESTAMP"),
            index=True,
        ),
    )
