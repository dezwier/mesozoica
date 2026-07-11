"""Fossil occurrence records synced from the Paleobiology Database."""

from __future__ import annotations

from decimal import Decimal
from typing import Optional

from sqlalchemy import Column, ForeignKey, Numeric, Text
from sqlmodel import Field, SQLModel


class Fossil(SQLModel, table=True):
    """PBDB fossil occurrence linked to a dinosaur genus."""

    __tablename__ = "fossil"

    id: int = Field(primary_key=True, description="PBDB occurrence_no")
    dinosaur_id: int = Field(
        sa_column=Column(
            "dinosaur_id",
            ForeignKey("dinosaur.id", ondelete="CASCADE"),
            nullable=False,
            index=True,
        ),
    )
    identified_name: Optional[str] = Field(default=None, max_length=255)
    latitude: Optional[Decimal] = Field(default=None, sa_column=Column(Numeric(9, 6)))
    longitude: Optional[Decimal] = Field(default=None, sa_column=Column(Numeric(9, 6)))
    country_code: Optional[str] = Field(default=None, max_length=2)
    state: Optional[str] = Field(default=None, max_length=100)
    geological_formation: Optional[str] = Field(default=None, max_length=255)
    min_age_ma: Optional[Decimal] = Field(default=None, sa_column=Column(Numeric(5, 2)))
    max_age_ma: Optional[Decimal] = Field(default=None, sa_column=Column(Numeric(5, 2)))
    early_interval: Optional[str] = Field(default=None, max_length=100)
    family: Optional[str] = Field(default=None, max_length=100)
    collection_name: Optional[str] = Field(default=None, max_length=255)
    collection_dates: Optional[str] = Field(default=None, max_length=100)
    stratcomments: Optional[str] = Field(default=None, sa_column=Column(Text))
    lithdescript: Optional[str] = Field(default=None, max_length=500)
    collectors: Optional[str] = Field(default=None, max_length=500)
    museum: Optional[str] = Field(default=None, max_length=100)
    pres_mode: Optional[str] = Field(default=None, max_length=50)
    preservation_quality: Optional[str] = Field(default=None, max_length=50)
    abund_value: Optional[int] = Field(default=None)
    abund_unit: Optional[str] = Field(default=None, max_length=50)
    description: Optional[str] = Field(
        default=None,
        sa_column=Column(Text),
        description="Human-readable site summary from PBDB location and stratigraphy notes",
    )
