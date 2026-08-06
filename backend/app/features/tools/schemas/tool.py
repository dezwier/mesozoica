"""Pydantic schemas for tool API responses. Owned by the tools feature."""

from __future__ import annotations

from datetime import datetime
from typing import Any

from pydantic import BaseModel, ConfigDict, Field


class OwnedOccurrenceThumb(BaseModel):
    """Viewer-owned occurrence thumbnail for catalog album tiles."""

    id: int
    version: str | None = None
    main_image_url: str | None = None
    spawn_date: datetime | None = None


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
    spawn_date: datetime | None = None
    version: str | None = None
    owned_occurrences: list[OwnedOccurrenceThumb] = Field(default_factory=list)
    remaining_duration_s: int | None = None
    total_duration_s: int | None = None


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


class RoutePointBody(BaseModel):
    lat: float
    lon: float


class ToolSessionStartRequest(BaseModel):
    """Start body; fields used depend on action_key of the tool."""

    route: list[RoutePointBody] | None = None
    origin_lat: float | None = None
    origin_lon: float | None = None
    lat: float | None = None
    lon: float | None = None
    site_id: int | None = None


class ToolSessionEventsSummary(BaseModel):
    discovered_site_ids: list[int] = Field(default_factory=list)
    discovered_count: int = 0
    pending_count: int = 0
    miss_count: int = 0
    done_count: int = 0


class ToolSessionResponse(BaseModel):
    session_id: int
    tool_id: int
    action_key: str
    status: str
    started_at: datetime
    expires_at: datetime | None = None
    ended_at: datetime | None = None
    used_duration_s: int | None = None
    stop_reason: str | None = None
    params: dict[str, Any] = Field(default_factory=dict)
    state: dict[str, Any] = Field(default_factory=dict)
    events_summary: ToolSessionEventsSummary = Field(
        default_factory=ToolSessionEventsSummary
    )
    tool_image_url: str | None = None


class ToolHistoryRoleEvent(BaseModel):
    """A user_tool role event (e.g. owned / obtained)."""

    action: str
    at: datetime


class ToolHistoryEntry(BaseModel):
    """Unified card history row: a use (session) or a role change."""

    kind: str  # "session" | "role"
    at: datetime
    session: ToolSessionResponse | None = None
    role: ToolHistoryRoleEvent | None = None


class ToolSessionListResponse(BaseModel):
    tool_id: int | None = None
    total_duration_s: int | None = None
    used_duration_s: int | None = None
    remaining_duration_s: int | None = None
    items: list[ToolSessionResponse] = Field(default_factory=list)
    history: list[ToolHistoryEntry] = Field(default_factory=list)


class UpdateToolParamsRequest(BaseModel):
    params: dict


class CollectToolRequest(BaseModel):
    """Admin collect body: curated image version folder name."""

    version: str = Field(
        ...,
        min_length=1,
        max_length=64,
        description="Curated image version folder (e.g. Original, Summer 26)",
    )


class ToolImageVersionItem(BaseModel):
    name: str
    run_date: str | None = None


class ToolImageVersionListResponse(BaseModel):
    items: list[ToolImageVersionItem]
