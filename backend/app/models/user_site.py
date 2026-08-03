"""User–site relationship (discovery, excavation, etc.)."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Optional

from sqlalchemy import Column, DateTime, ForeignKey, Integer, UniqueConstraint, text
from sqlmodel import Field, SQLModel

USER_SITE_ROLE_DISCOVERER = "discoverer"
USER_SITE_ROLE_DOCUMENTER = "documenter"
USER_SITE_ROLE_EXCAVATOR = "excavator"
USER_SITE_ROLE_EXHAUSTER = "exhauster"
USER_SITE_ROLE_PROTECTOR = "protector"
USER_SITE_ROLE_DISGUISER = "disguiser"

# Roles that participate in global site status (latest timestamp wins).
STATUS_ROLES: tuple[str, ...] = (
    USER_SITE_ROLE_DISCOVERER,
    USER_SITE_ROLE_DOCUMENTER,
    USER_SITE_ROLE_EXCAVATOR,
    USER_SITE_ROLE_EXHAUSTER,
    USER_SITE_ROLE_PROTECTOR,
)

USER_SITE_ROLES: tuple[str, ...] = (
    *STATUS_ROLES,
    USER_SITE_ROLE_DISGUISER,
)

SITE_STATUS_HIDDEN = "hidden"
SITE_STATUS_DISCOVERED = "discovered"
SITE_STATUS_DOCUMENTED = "documented"
SITE_STATUS_EXCAVATION = "excavation"
SITE_STATUS_EXHAUSTED = "exhausted"
SITE_STATUS_PROTECTED = "protected"

SITE_STATUSES: tuple[str, ...] = (
    SITE_STATUS_HIDDEN,
    SITE_STATUS_DISCOVERED,
    SITE_STATUS_DOCUMENTED,
    SITE_STATUS_EXCAVATION,
    SITE_STATUS_EXHAUSTED,
    SITE_STATUS_PROTECTED,
)

ROLE_TO_STATUS: dict[str, str] = {
    USER_SITE_ROLE_DISCOVERER: SITE_STATUS_DISCOVERED,
    USER_SITE_ROLE_DOCUMENTER: SITE_STATUS_DOCUMENTED,
    USER_SITE_ROLE_EXCAVATOR: SITE_STATUS_EXCAVATION,
    USER_SITE_ROLE_EXHAUSTER: SITE_STATUS_EXHAUSTED,
    USER_SITE_ROLE_PROTECTOR: SITE_STATUS_PROTECTED,
}


def role_to_status(role: str | None) -> str:
    """Map a user_site role to API status; missing role → hidden."""
    if role is None:
        return SITE_STATUS_HIDDEN
    return ROLE_TO_STATUS.get(role, SITE_STATUS_HIDDEN)


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


class UserSite(SQLModel, table=True):
    """Links a user to a site with a role; latest role by timestamp = site status."""

    __tablename__ = "user_site"
    __table_args__ = (
        UniqueConstraint("user_id", "site_id", "role", name="uq_user_site_user_site_role"),
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
    site_id: int = Field(
        sa_column=Column(
            Integer,
            ForeignKey("site.site_id", ondelete="CASCADE"),
            nullable=False,
            index=True,
        ),
    )
    role: str = Field(
        max_length=16,
        description=(
            "discoverer, documenter, excavator, exhauster, protector, or disguiser"
        ),
    )
    source_session_id: Optional[int] = Field(
        default=None,
        sa_column=Column(
            Integer,
            ForeignKey("tool_session.id", ondelete="SET NULL"),
            nullable=True,
            index=True,
        ),
        description="Tool session that granted this role (e.g. aerial discover)",
    )
    explored_distance_m: float = Field(
        default=0.0,
        description=(
            "Meters walked inside site_visibility_m (discoverer row only)"
        ),
    )
    documented: bool = Field(
        default=False,
        description=(
            "True when all five dimension accuracies reached 100%; "
            "exploration meters are frozen"
        ),
    )
    was_first: bool = Field(
        default=False,
        description=(
            "True when this role grant was the first for the site "
            "(first discoverer / first documenter)"
        ),
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
