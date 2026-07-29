"""Pydantic schemas for tool API responses."""

from __future__ import annotations

from typing import Any

from pydantic import BaseModel, ConfigDict, Field


class ToolSummary(BaseModel):
    """Card-facing tool fields."""

    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    category: str
    scientific_tool: str
    description: str
    rarity: int
    action: str = "Use"
    main_image_url: str | None = None
    level: int | None = None
    tool_type_id: int | None = None
    params: dict[str, Any] = Field(default_factory=dict)
    base_params: dict[str, Any] = Field(default_factory=dict)


class ToolListResponse(BaseModel):
    items: list[ToolSummary]
    total: int
    limit: int
    offset: int
    has_next: bool


class ToolCategoryItem(BaseModel):
    value: str
    label: str


class ToolCategoryListResponse(BaseModel):
    items: list[ToolCategoryItem]
