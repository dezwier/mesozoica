"""Queued field-site survey jobs (one row per site; lazy fossil generation). Owned by the field feature."""

from __future__ import annotations

from datetime import datetime
from typing import Optional

from sqlmodel import Field, SQLModel


class FieldSurveyJob(SQLModel, table=True):
    __tablename__ = "field_survey_job"

    id: Optional[int] = Field(default=None, primary_key=True)
    site_id: int = Field(unique=True, index=True)
    initiated_by_user_id: int
    status: str = Field(default="pending", max_length=16, index=True)
    fossil_count: Optional[int] = Field(default=None)
    attempts: int = Field(default=0)
    worker_id: Optional[str] = Field(default=None, max_length=64)
    error_message: Optional[str] = Field(default=None, max_length=2000)
    created_at: datetime = Field(default_factory=datetime.utcnow)
    started_at: Optional[datetime] = Field(default=None)
    finished_at: Optional[datetime] = Field(default=None)
