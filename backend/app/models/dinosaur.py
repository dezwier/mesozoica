"""Dinosaur master data synced from Wikipedia."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Optional

from sqlalchemy import Column, JSON, Text
from sqlmodel import Field, SQLModel


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


class Dinosaur(SQLModel, table=True):
    """Wikipedia-sourced dinosaur genus record."""

    __tablename__ = "dinosaur"

    id: Optional[int] = Field(default=None, primary_key=True)
    name: str = Field(index=True, max_length=255)
    wikipedia_page_id: int = Field(unique=True, index=True)
    wikipedia_title: str = Field(unique=True, max_length=255)
    birth: Optional[float] = Field(default=None, description="Earliest appearance in Ma")
    death: Optional[float] = Field(default=None, description="Latest extinction in Ma")
    period: Optional[str] = Field(default=None, max_length=255)
    cladogram: dict[str, Any] = Field(default_factory=dict, sa_column=Column(JSON, nullable=False))
    diet_type: Optional[str] = Field(default=None, max_length=64)
    length: Optional[str] = Field(default=None, max_length=128)
    mass: Optional[str] = Field(default=None, max_length=128)
    location: Optional[str] = Field(default=None, max_length=512)
    short_description: Optional[str] = Field(default=None, sa_column=Column(Text))
    long_description: Optional[str] = Field(default=None, sa_column=Column(Text))
    article: Optional[str] = Field(default=None, sa_column=Column(Text))
    article_date: Optional[datetime] = Field(default=None)
    insert_date: datetime = Field(default_factory=_utc_now)
    main_image_url: Optional[str] = Field(default=None, max_length=2048)
    llm_enriched: bool = Field(default=False, index=True)
