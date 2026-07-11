"""Fossil occurrence records synced from the Paleobiology Database."""

from __future__ import annotations

from decimal import Decimal
from typing import Optional

from sqlalchemy import Column, ForeignKey, Numeric
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
