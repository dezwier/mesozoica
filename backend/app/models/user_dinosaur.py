"""User–dinosaur relationship (collection roles; status derived from latest role)."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Optional

from sqlalchemy import Column, DateTime, ForeignKey, Integer, UniqueConstraint, text
from sqlmodel import Field, SQLModel

USER_DINOSAUR_ROLE_DISCOVERER = "discoverer"

USER_DINOSAUR_ROLES: tuple[str, ...] = (USER_DINOSAUR_ROLE_DISCOVERER,)

DINOSAUR_STATUS_HIDDEN = "hidden"
DINOSAUR_STATUS_DISCOVERED = "discovered"

DINOSAUR_STATUSES: tuple[str, ...] = (
    DINOSAUR_STATUS_HIDDEN,
    DINOSAUR_STATUS_DISCOVERED,
)

ROLE_TO_STATUS: dict[str, str] = {
    USER_DINOSAUR_ROLE_DISCOVERER: DINOSAUR_STATUS_DISCOVERED,
}


def role_to_status(role: str | None) -> str:
    """Map a user_dinosaur role to API status; missing role → hidden."""
    if role is None:
        return DINOSAUR_STATUS_HIDDEN
    return ROLE_TO_STATUS.get(role, DINOSAUR_STATUS_HIDDEN)


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


class UserDinosaur(SQLModel, table=True):
    """Links a user to a dinosaur with a role; latest role by timestamp = status."""

    __tablename__ = "user_dinosaur"
    __table_args__ = (
        UniqueConstraint(
            "user_id",
            "dinosaur_id",
            "role",
            name="uq_user_dinosaur_user_dinosaur_role",
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
    dinosaur_id: int = Field(
        sa_column=Column(
            Integer,
            ForeignKey("dinosaur.id", ondelete="CASCADE"),
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
