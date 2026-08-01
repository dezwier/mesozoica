"""Pydantic schemas for tool API responses."""

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
    # Inventory occurrence obtain time; null for catalog rows.
    spawn_date: datetime | None = None
    # Curated image version folder; set for inventory occurrences.
    version: str | None = None
    # Catalog mode only: viewer's owned occurrences of this type (gallery thumbs).
    owned_occurrences: list[OwnedOccurrenceThumb] = Field(default_factory=list)


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


class OrbitSurveySessionResponse(BaseModel):
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


class FormationMapSessionStartRequest(BaseModel):
    lat: float | None = None
    lon: float | None = None


class FormationMapSessionResponse(BaseModel):
    session_id: int
    action_key: str
    status: str
    tool_id: int
    duration_minutes: int
    accuracy: float
    wideness_m: float
    cell_size_m: float
    center_lat: float
    center_lon: float
    started_at: datetime
    expires_at: datetime
    cancelled_at: datetime | None = None


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
