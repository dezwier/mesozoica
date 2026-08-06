"""Dinosaur catalog genus identity (Wikipedia-synced master key). Owned by the specimens feature."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Optional

from sqlalchemy import Column, ForeignKey, Integer
from sqlmodel import Field, SQLModel


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


class DinosaurType(SQLModel, table=True):
    """Wikipedia-sourced dinosaur genus identity (one row per genus).

    Article text, parsed fields, and LLM enrichment live on
    ``dinosaur_type_revision``; this row points at the live revision via
    ``current_revision_id``.
    """

    __tablename__ = "dinosaur_type"

    id: Optional[int] = Field(default=None, primary_key=True)
    name: str = Field(index=True, max_length=255)
    wikipedia_page_id: int = Field(unique=True, index=True)
    wikipedia_title: str = Field(unique=True, max_length=255)
    insert_date: datetime = Field(default_factory=_utc_now)
    fossils_insert_time: Optional[datetime] = Field(
        default=None,
        description="Last time PBDB fossil occurrences were retrieved for this genus",
    )
    main_image_url: Optional[str] = Field(default=None, max_length=2048)
    current_revision_id: Optional[int] = Field(
        default=None,
        sa_column=Column(
            Integer,
            ForeignKey(
                "dinosaur_type_revision.id",
                ondelete="SET NULL",
                use_alter=True,
                name="fk_dinosaur_type_current_revision_id",
            ),
            nullable=True,
            index=True,
        ),
    )
