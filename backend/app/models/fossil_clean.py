"""Normalized fossil occurrence records derived from PBDB fossil data."""

from __future__ import annotations

from decimal import Decimal
from typing import Optional

from sqlalchemy import Column, ForeignKey, Numeric, Text
from sqlmodel import Field, SQLModel


class FossilClean(SQLModel, table=True):
    """One row per fossil occurrence with cleaned categorical fields."""

    __tablename__ = "fossil_clean"

    fossil_id: int = Field(
        sa_column=Column(
            "fossil_id",
            ForeignKey("fossil.id", ondelete="CASCADE"),
            primary_key=True,
            nullable=False,
        ),
        description="PBDB occurrence_no",
    )
    site_id: int = Field(
        sa_column=Column(
            "site_id",
            ForeignKey("site_clean.site_id", ondelete="CASCADE"),
            nullable=False,
            index=True,
        ),
    )
    dinosaur_id: int = Field(
        sa_column=Column(
            "dinosaur_id",
            ForeignKey("dinosaur.id", ondelete="CASCADE"),
            nullable=False,
            index=True,
        ),
    )
    name: Optional[str] = Field(default=None, max_length=255)
    type: str = Field(max_length=20, description="body or trace")
    sub_category: Optional[str] = Field(default=None, max_length=255)
    preservation_quality: Optional[str] = Field(default=None, max_length=50)
    min_age_ma: Optional[Decimal] = Field(default=None, sa_column=Column(Numeric(5, 2)))
    max_age_ma: Optional[Decimal] = Field(default=None, sa_column=Column(Numeric(5, 2)))
    collection_year_min: Optional[int] = Field(default=None)
    collection_year_max: Optional[int] = Field(default=None)
    comment: Optional[str] = Field(default=None, sa_column=Column(Text))
