"""Typed site_generation document models."""

from __future__ import annotations

from pydantic import BaseModel, Field, model_validator

class SiteGenerationLazyConfig(BaseModel):
    """Lazy ensure density: max N sites per axis-aligned square cell (server-only)."""

    model_config = {"frozen": True}

    max_sites_per_cell: int = 50
    cell_size_m: float = 500.0
    min_separation_km: float = 0.01
    nearby_radius_km: float = 100.0
    closest_neighbor_count: int = 20
    weight_global: float = 0.25
    weight_nearby: float = 0.50
    weight_closest: float = 0.25
    max_coordinate_attempts: int = 200

    @model_validator(mode="after")
    def _validate_lazy(self) -> SiteGenerationLazyConfig:
        if self.max_sites_per_cell < 1:
            raise ValueError("max_sites_per_cell must be >= 1")
        if self.cell_size_m <= 0:
            raise ValueError("cell_size_m must be > 0")
        total = self.weight_global + self.weight_nearby + self.weight_closest
        if abs(total - 1.0) > 1e-6:
            raise ValueError("lazy distribution weights must sum to 1.0")
        return self

    @property
    def cell_size_km(self) -> float:
        return float(self.cell_size_m) / 1000.0


class SiteGenerationBulkConfig(BaseModel):
    model_config = {"frozen": True}

    max_items: int = 100
    min_separation_km: float = 0.01
    nearby_radius_km: float = 100.0
    closest_neighbor_count: int = 20
    weight_global: float = 0.25
    weight_nearby: float = 0.50
    weight_closest: float = 0.25
    max_coordinate_attempts: int = 200

    @model_validator(mode="after")
    def _validate_weights(self) -> SiteGenerationBulkConfig:
        total = self.weight_global + self.weight_nearby + self.weight_closest
        if abs(total - 1.0) > 1e-6:
            raise ValueError("bulk distribution weights must sum to 1.0")
        return self


class SiteGenerationClientConfig(BaseModel):
    model_config = {"frozen": True}

    nearby_radius_km: float = 1.0


class SiteGenerationConfig(BaseModel):
    model_config = {"frozen": True}

    lazy: SiteGenerationLazyConfig = Field(default_factory=SiteGenerationLazyConfig)
    bulk: SiteGenerationBulkConfig = Field(default_factory=SiteGenerationBulkConfig)
    client: SiteGenerationClientConfig = Field(
        default_factory=SiteGenerationClientConfig
    )


# ---------------------------------------------------------------------------
# Skill 1 — Field Survey (discovery + stewardship + clearing)
# ---------------------------------------------------------------------------


