"""Geological period and rock-type combinations for fossil sites."""

from __future__ import annotations

from sqlmodel import Field, SQLModel, UniqueConstraint


class SiteType(SQLModel, table=True):
    """One row per distinct period + rock_type combination."""

    __tablename__ = "site_type"
    __table_args__ = (UniqueConstraint("period", "rock_type", name="uq_site_type_period_rock_type"),)

    id: int | None = Field(default=None, primary_key=True)
    period: str = Field(max_length=20, description="triassic, jurassic, or cretaceous")
    rock_type: str = Field(max_length=100)
    main_image_url: str | None = Field(default=None, max_length=512)
