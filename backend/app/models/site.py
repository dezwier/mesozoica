"""Normalized fossil collection site records derived from PBDB fossil data."""

from __future__ import annotations

from decimal import Decimal
from typing import Optional

from sqlalchemy import Column, ForeignKey, Numeric
from sqlmodel import Field, SQLModel

from app.models.data_source import DATA_SOURCE_ARCHIVE

HOW_DISCOVERED_WALK = "walk"
HOW_DISCOVERED_AERIAL_RECON = "aerial_recon"
HOW_DISCOVERED_MANUAL = "manual"
HOW_DISCOVERED_VALUES = (
    HOW_DISCOVERED_WALK,
    HOW_DISCOVERED_AERIAL_RECON,
    HOW_DISCOVERED_MANUAL,
)


class Site(SQLModel, table=True):
    """One row per PBDB collection locality (collection_no)."""

    __tablename__ = "site"

    site_id: int = Field(primary_key=True, description="PBDB collection_no")
    latitude: Optional[Decimal] = Field(default=None, sa_column=Column(Numeric(9, 6)))
    longitude: Optional[Decimal] = Field(default=None, sa_column=Column(Numeric(9, 6)))
    country_code: Optional[str] = Field(default=None, max_length=2)
    state: Optional[str] = Field(default=None, max_length=100)
    rock_type: Optional[str] = Field(default=None, max_length=100)
    formation: Optional[str] = Field(default=None, max_length=255)
    min_age_ma: Optional[Decimal] = Field(default=None, sa_column=Column(Numeric(5, 2)))
    max_age_ma: Optional[Decimal] = Field(default=None, sa_column=Column(Numeric(5, 2)))
    period: Optional[str] = Field(
        default=None,
        max_length=20,
        description="triassic, jurassic, or cretaceous (derived from min/max_age_ma)",
    )
    site_type_id: Optional[int] = Field(
        default=None,
        sa_column=Column(
            "site_type_id",
            ForeignKey("site_type.id", ondelete="SET NULL"),
            nullable=True,
            index=True,
        ),
    )
    data_source: str = Field(
        default=DATA_SOURCE_ARCHIVE,
        max_length=16,
        index=True,
        description="archive (PBDB/wiki) or field (procedural)",
    )
    how_discovered: Optional[str] = Field(
        default=None,
        max_length=32,
        description="First discovery method: walk, aerial_recon, or manual",
    )
    odd_dino_count: Optional[float] = Field(
        default=None,
        description="Field-site Uniform(0,1) score biasing dinosaur count on survey",
    )
    odd_fossil_count: Optional[float] = Field(
        default=None,
        description="Field-site Uniform(0,1) score biasing cards per dinosaur",
    )
    odd_completeness: Optional[float] = Field(
        default=None,
        description="Field-site Uniform(0,1) score biasing fossil completeness",
    )
    odd_quality: Optional[float] = Field(
        default=None,
        description="Field-site Uniform(0,1) score biasing preservation quality",
    )
    odd_depth: Optional[float] = Field(
        default=None,
        description="Field-site Uniform(0,1) score biasing burial depth",
    )
