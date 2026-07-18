"""Queued field-site ensure jobs (one row per spatial cell)."""

from __future__ import annotations

from datetime import datetime
from typing import Optional

from sqlmodel import Field, SQLModel


class FieldEnsureJob(SQLModel, table=True):
    __tablename__ = "field_ensure_job"

    id: Optional[int] = Field(default=None, primary_key=True)
    cell_key: str = Field(max_length=64, unique=True, index=True)
    lat: float
    lon: float
    radius_km: float
    missing_count: int = Field(default=0)
    reason: Optional[str] = Field(default=None, max_length=32)
    status: str = Field(default="pending", max_length=16, index=True)
    attempts: int = Field(default=0)
    worker_id: Optional[str] = Field(default=None, max_length=64)
    error_message: Optional[str] = Field(default=None, max_length=2000)
    created_at: datetime = Field(default_factory=datetime.utcnow)
    started_at: Optional[datetime] = Field(default=None)
    finished_at: Optional[datetime] = Field(default=None)
