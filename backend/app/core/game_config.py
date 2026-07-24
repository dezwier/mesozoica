"""Load shared game-mechanics YAML (control board under app/game_config/)."""

from __future__ import annotations

import os
from functools import lru_cache
from pathlib import Path
from typing import Any

import yaml
from pydantic import BaseModel, Field, field_validator, model_validator

_PACKAGE_DIR = Path(__file__).resolve().parent
_DEFAULT_CONFIG_DIR = _PACKAGE_DIR.parent / "game_config"


def _load_yaml(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as handle:
        data = yaml.safe_load(handle)
    if data is None:
        return {}
    if not isinstance(data, dict):
        raise ValueError(f"Invalid game config (expected mapping): {path}")
    return data


def _weights_must_sum_to_one(weights: dict[int, float], *, label: str) -> None:
    total = sum(weights.values())
    if abs(total - 1.0) > 1e-6:
        raise ValueError(f"{label} must sum to 1.0 (got {total})")


class SiteGenerationLazyConfig(BaseModel):
    model_config = {"frozen": True}

    min_sites_in_radius: int = 100
    radius_km: float = 1.0
    min_separation_km: float = 0.01
    nearby_radius_km: float = 100.0
    closest_neighbor_count: int = 20
    weight_global: float = 0.25
    weight_nearby: float = 0.50
    weight_closest: float = 0.25
    max_coordinate_attempts: int = 200

    @model_validator(mode="after")
    def _validate_weights(self) -> SiteGenerationLazyConfig:
        total = self.weight_global + self.weight_nearby + self.weight_closest
        if abs(total - 1.0) > 1e-6:
            raise ValueError("lazy distribution weights must sum to 1.0")
        return self


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

    ensure_move_threshold_m: float = 500.0
    nearby_radius_km: float = 1.0


class SiteGenerationConfig(BaseModel):
    model_config = {"frozen": True}

    lazy: SiteGenerationLazyConfig = Field(default_factory=SiteGenerationLazyConfig)
    bulk: SiteGenerationBulkConfig = Field(default_factory=SiteGenerationBulkConfig)
    client: SiteGenerationClientConfig = Field(
        default_factory=SiteGenerationClientConfig
    )


class SiteDiscoveryClientConfig(BaseModel):
    model_config = {"frozen": True}

    auto_discover_radius_m: float = 50.0
    cache_radius_km: float = 1.0
    cache_refresh_move_threshold_m: float = 500.0
    discover_fail_retry_s: int = 20


class SiteDiscoveryConfig(BaseModel):
    model_config = {"frozen": True}

    max_distance_m: float = 50.0
    discovery_chance: float = 0.3
    client: SiteDiscoveryClientConfig = Field(
        default_factory=SiteDiscoveryClientConfig
    )

    @field_validator("discovery_chance")
    @classmethod
    def _validate_discovery_chance(cls, value: float) -> float:
        if value < 0.0 or value > 1.0:
            raise ValueError("discovery_chance must be between 0.0 and 1.0")
        return value


class FossilGenerationDefaults(BaseModel):
    model_config = {"frozen": True}

    subcategory: str = "teeth"
    completeness: str = "fragmentary"
    quality: str = "moderate"


class FossilDepthBucket(BaseModel):
    model_config = {"frozen": True}

    weight: float
    min_cm: int
    max_cm: int

    @model_validator(mode="after")
    def _validate_range(self) -> FossilDepthBucket:
        if self.weight < 0:
            raise ValueError("depth bucket weight must be >= 0")
        if self.min_cm < 0 or self.max_cm < 0:
            raise ValueError("depth_cm bounds must be >= 0")
        if self.max_cm < self.min_cm:
            raise ValueError("depth bucket max_cm must be >= min_cm")
        return self


class DinoCountThreshold(BaseModel):
    model_config = {"frozen": True}

    max_odd: float
    count: int

    @model_validator(mode="after")
    def _validate_threshold(self) -> DinoCountThreshold:
        if self.max_odd < 0.0 or self.max_odd > 1.0:
            raise ValueError("dino_count_thresholds max_odd must be in [0, 1]")
        if self.count < 0:
            raise ValueError("dino_count_thresholds count must be >= 0")
        return self


class FossilOddNoiseConfig(BaseModel):
    """Per-sampler ±noise for clamp(odd + Uniform(-n, +n), 0, 1)."""

    model_config = {"frozen": True}

    dino_count: float = 0.3
    fossil_count: float = 0.3
    completeness: float = 0.3
    quality: float = 0.3
    depth: float = 0.3

    @field_validator(
        "dino_count",
        "fossil_count",
        "completeness",
        "quality",
        "depth",
    )
    @classmethod
    def _validate_non_negative(cls, value: float) -> float:
        if value < 0.0:
            raise ValueError("odd_noise values must be >= 0")
        return value


class FossilGenerationConfig(BaseModel):
    model_config = {"frozen": True}

    odd_noise: FossilOddNoiseConfig = Field(default_factory=FossilOddNoiseConfig)
    dino_count_thresholds: list[DinoCountThreshold] = Field(
        default_factory=lambda: [
            DinoCountThreshold(max_odd=0.10, count=0),
            DinoCountThreshold(max_odd=0.60, count=1),
            DinoCountThreshold(max_odd=0.80, count=2),
            DinoCountThreshold(max_odd=0.90, count=3),
            DinoCountThreshold(max_odd=0.95, count=4),
            DinoCountThreshold(max_odd=1.00, count=5),
        ]
    )
    card_count_weights: dict[int, float] = Field(
        default_factory=lambda: {
            1: 0.25,
            2: 0.25,
            3: 0.20,
            4: 0.15,
            5: 0.10,
            6: 0.05,
        }
    )
    depth_buckets: list[FossilDepthBucket] = Field(
        default_factory=lambda: [
            FossilDepthBucket(weight=0.20, min_cm=0, max_cm=0),
            FossilDepthBucket(weight=0.30, min_cm=1, max_cm=50),
            FossilDepthBucket(weight=0.30, min_cm=51, max_cm=200),
            FossilDepthBucket(weight=0.10, min_cm=201, max_cm=500),
            FossilDepthBucket(weight=0.10, min_cm=501, max_cm=1000),
        ]
    )
    defaults: FossilGenerationDefaults = Field(
        default_factory=FossilGenerationDefaults
    )

    @field_validator("card_count_weights", mode="before")
    @classmethod
    def _coerce_int_keys(cls, value: Any) -> dict[int, float]:
        if not isinstance(value, dict):
            raise TypeError("weights must be a mapping")
        return {int(k): float(v) for k, v in value.items()}

    @model_validator(mode="after")
    def _validate_weights(self) -> FossilGenerationConfig:
        if not self.dino_count_thresholds:
            raise ValueError("dino_count_thresholds must not be empty")
        prev = -1.0
        for threshold in self.dino_count_thresholds:
            if threshold.max_odd < prev:
                raise ValueError("dino_count_thresholds must be ordered by max_odd")
            prev = threshold.max_odd
        if abs(self.dino_count_thresholds[-1].max_odd - 1.0) > 1e-6:
            raise ValueError("dino_count_thresholds final max_odd must be 1.0")
        _weights_must_sum_to_one(self.card_count_weights, label="card_count_weights")
        if not self.depth_buckets:
            raise ValueError("depth_buckets must not be empty")
        total = sum(bucket.weight for bucket in self.depth_buckets)
        if abs(total - 1.0) > 1e-6:
            raise ValueError(f"depth_buckets weights must sum to 1.0 (got {total})")
        return self


class FossilDiscoveryConfig(BaseModel):
    model_config = {"frozen": True}

    enabled: bool = False


class FossilExcavationConfig(BaseModel):
    model_config = {"frozen": True}

    enabled: bool = False


class AerialMissionActionConfig(BaseModel):
    model_config = {"frozen": True}

    max_route_km: float = 100.0
    loop_endpoint_tolerance_m: float = 75.0
    flight_speed_kmh: float = 50.0
    discovery_chance: float = 0.2
    discovery_distance_m: float = 200.0
    ensure_sample_spacing_km: float = 0.5
    ensure_timeout_s: int = 600
    short_route_warn_fraction: float = 0.7
    stats_explanation: str = (
        "Scout loops fly at this speed within the max range; sites within "
        "discovery distance are rolled at the listed chance."
    )

    @field_validator("discovery_chance")
    @classmethod
    def _validate_discovery_chance(cls, value: float) -> float:
        if value < 0.0 or value > 1.0:
            raise ValueError("discovery_chance must be between 0.0 and 1.0")
        return value

    @field_validator("short_route_warn_fraction")
    @classmethod
    def _validate_short_route_warn_fraction(cls, value: float) -> float:
        if value < 0.0 or value > 1.0:
            raise ValueError("short_route_warn_fraction must be between 0.0 and 1.0")
        return value


# Back-compat alias for older imports/tests.
AerialReconActionConfig = AerialMissionActionConfig


class ToolActionsConfig(BaseModel):
    model_config = {"frozen": True}

    aerial_recon: AerialMissionActionConfig = Field(
        default_factory=AerialMissionActionConfig
    )
    aerial_scout: AerialMissionActionConfig = Field(
        default_factory=lambda: AerialMissionActionConfig(
            max_route_km=30.0,
            flight_speed_kmh=35.0,
            discovery_chance=0.008,
            discovery_distance_m=120.0,
            stats_explanation=(
                "Drone loops fly at this speed within the max range; sites within "
                "discovery distance are rolled at the listed chance."
            ),
        )
    )


class GameConfig(BaseModel):
    model_config = {"frozen": True}

    site_generation: SiteGenerationConfig
    site_discovery: SiteDiscoveryConfig
    fossil_generation: FossilGenerationConfig
    fossil_discovery: FossilDiscoveryConfig
    fossil_excavation: FossilExcavationConfig
    tool_actions: ToolActionsConfig


def resolve_game_config_dir() -> Path:
    override = os.environ.get("GAME_CONFIG_DIR", "").strip()
    if override:
        return Path(override)
    return _DEFAULT_CONFIG_DIR


def load_game_config(config_dir: Path | None = None) -> GameConfig:
    """Load and validate all domain YAML files from the control board directory."""
    directory = config_dir or resolve_game_config_dir()
    if not directory.is_dir():
        raise FileNotFoundError(f"Missing game config directory: {directory}")

    return GameConfig(
        site_generation=SiteGenerationConfig.model_validate(
            _load_yaml(directory / "site_generation.yaml")
        ),
        site_discovery=SiteDiscoveryConfig.model_validate(
            _load_yaml(directory / "site_discovery.yaml")
        ),
        fossil_generation=FossilGenerationConfig.model_validate(
            _load_yaml(directory / "fossil_generation.yaml")
        ),
        fossil_discovery=FossilDiscoveryConfig.model_validate(
            _load_yaml(directory / "fossil_discovery.yaml")
        ),
        fossil_excavation=FossilExcavationConfig.model_validate(
            _load_yaml(directory / "fossil_excavation.yaml")
        ),
        tool_actions=ToolActionsConfig.model_validate(
            _load_yaml(directory / "tool_actions.yaml")
        ),
    )


@lru_cache(maxsize=1)
def get_game_config() -> GameConfig:
    """Process-wide singleton; clear with ``get_game_config.cache_clear()`` in tests."""
    return load_game_config()
