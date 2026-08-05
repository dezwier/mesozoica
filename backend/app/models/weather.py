"""Persisted 15-minute weather observations and forecasts per ~5 km cell."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Optional

from sqlalchemy import Column, DateTime, UniqueConstraint
from sqlmodel import Field, SQLModel


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


class Weather(SQLModel, table=True):
    """One 15-minute weather sample for a weather grid cell."""

    __tablename__ = "weather"
    __table_args__ = (
        UniqueConstraint("cell_i", "cell_j", "valid_at", name="uq_weather_cell_valid_at"),
    )

    id: Optional[int] = Field(default=None, primary_key=True)
    cell_i: int = Field(index=True, description="Weather grid row index (~5 km)")
    cell_j: int = Field(index=True, description="Weather grid column index (~5 km)")
    center_lat: float
    center_lon: float
    valid_at: datetime = Field(
        sa_column=Column(DateTime(timezone=True), nullable=False, index=True),
        description="UTC 15-minute slot this row describes",
    )
    is_forecast: bool = Field(
        default=False,
        description="True when valid_at was in the future at fetch time",
    )
    weather_type: str = Field(max_length=32)
    temperature_c: float
    wmo_code: int = Field(default=-1)
    fetched_at: datetime = Field(
        default_factory=_utc_now,
        sa_column=Column(DateTime(timezone=True), nullable=False),
    )
