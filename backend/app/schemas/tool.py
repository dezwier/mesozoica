"""Pydantic schemas for tool API responses."""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict


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
