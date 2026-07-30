"""Pydantic schemas for tool API responses."""

from __future__ import annotations

from datetime import datetime
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
    # Inventory occurrence obtain time; null for catalog rows.
    spawn_date: datetime | None = None


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


class AerialMissionRequest(BaseModel):
    route: list[RoutePointBody] = Field(min_length=3)
    origin_lat: float
    origin_lon: float


class AerialMissionItem(BaseModel):
    mission_id: int
    action_key: str
    status: str
    route: list[RoutePointBody]
    route_length_km: float
    flight_duration_s: int
    flight_speed_kmh: float
    max_route_km: float
    discovery_chance: float
    discovery_distance_m: float
    flight_started_at: datetime | None = None
    flight_ends_at: datetime | None = None
    created_at: datetime
    tool_id: int
    tool_image_url: str | None = None
    discovered_site_ids: list[int] = Field(default_factory=list)


class AerialMissionListResponse(BaseModel):
    items: list[AerialMissionItem]


class AerialMissionResponse(BaseModel):
    mission_id: int
    action_key: str
    status: str
    route: list[RoutePointBody]
    route_length_km: float
    flight_duration_s: int
    flight_speed_kmh: float
    max_route_km: float
    discovery_chance: float
    discovery_distance_m: float
    flight_started_at: datetime | None = None
    flight_ends_at: datetime | None = None
    created_at: datetime
    tool_id: int
    tool_image_url: str | None = None
    discovered_site_ids: list[int] = Field(default_factory=list)


class GuidanceSessionResponse(BaseModel):
    session_id: int
    action_key: str
    status: str
    tool_id: int
    discovery_chance: float | None = None
    direction_exactness: float | None = None
    distance_exactness: float | None = None
    duration_minutes: int
    started_at: datetime
    expires_at: datetime
    cancelled_at: datetime | None = None


class FormationMapSessionResponse(BaseModel):
    session_id: int
    action_key: str
    status: str
    tool_id: int
    duration_minutes: int
    accuracy: float
    range: float
    min_range_m: float
    max_range_m: float
    started_at: datetime
    expires_at: datetime
    cancelled_at: datetime | None = None


class UpdateToolParamsRequest(BaseModel):
    params: dict
