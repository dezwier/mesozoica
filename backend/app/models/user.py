"""User account and paleontology profile."""

from __future__ import annotations

import hashlib
from datetime import datetime, timezone
from typing import Optional

from sqlalchemy import Column, JSON
from sqlmodel import Field, SQLModel


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


class User(SQLModel, table=True):
    """App user with auth credentials and paleontology profile fields."""

    __tablename__ = "user"

    id: Optional[int] = Field(default=None, primary_key=True)
    username: str = Field(unique=True, index=True, max_length=50)
    email: str = Field(unique=True, index=True, max_length=255)
    password: Optional[str] = Field(default=None, max_length=128)
    firebase_uid: Optional[str] = Field(default=None, unique=True, index=True)
    unlinked_firebase_providers: Optional[str] = Field(default=None, max_length=255)
    created_at: datetime = Field(default_factory=_utc_now)

    full_name: Optional[str] = Field(default=None, max_length=200)
    image_url: Optional[str] = Field(default=None, max_length=2048)

    display_name: str = Field(default="Paleontologist", max_length=200)
    specialization: str = Field(default="Paleontologist", max_length=200)
    years_of_experience: int = Field(default=0)
    notable_discovery: str = Field(default="", max_length=500)
    favorite_era: str = Field(default="", max_length=200)
    xp: int = Field(default=0)
    level: int = Field(default=1)
    achievements: list[str] = Field(default_factory=list, sa_column=Column(JSON, nullable=False))
    bio: str = Field(default="", max_length=2000)
    current_location: str = Field(default="", max_length=200)
    is_admin: bool = Field(default=False)

    @staticmethod
    def hash_password(password: str) -> str:
        return hashlib.sha256(password.encode("utf-8")).hexdigest()

    def verify_password(self, password: str) -> bool:
        if self.password is None:
            return False
        return self.password == self.hash_password(password)
