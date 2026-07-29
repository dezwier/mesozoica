"""Paleontological field tool catalog entries (types)."""

from __future__ import annotations

from typing import Any

from sqlalchemy import JSON, Column
from sqlmodel import Field, SQLModel


class ToolType(SQLModel, table=True):
    """One row per branded field tool in the catalog."""

    __tablename__ = "tool_type"

    id: int | None = Field(default=None, primary_key=True)
    name: str = Field(max_length=100, unique=True, index=True)
    category: str = Field(max_length=50)
    scientific_tool: str = Field(max_length=100)
    description: str = Field(max_length=500)
    rarity: int = Field(ge=1, le=5)
    action: str = Field(default="Use", max_length=40)
    main_image_url: str | None = Field(default=None, max_length=512)
    default_params_json: dict[str, Any] = Field(
        default_factory=dict,
        sa_column=Column(JSON, nullable=False),
    )
