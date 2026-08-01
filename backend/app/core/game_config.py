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


def _clamp_unit_interval(value: float, *, label: str) -> float:
    if value < 0.0 or value > 1.0:
        raise ValueError(f"{label} must be between 0.0 and 1.0")
    return value


class GuidanceActionConfig(BaseModel):
    """Knobs for site-guidance tools (compass / proximity / navigator)."""

    model_config = {"frozen": True}

    duration_minutes: int = 15
    # Single-axis tools (geo_compass direction, proximity_scanner distance).
    exactness: float | None = None
    # Site navigator dual axes.
    direction_exactness: float | None = None
    distance_exactness: float | None = None
    discovery_chance: float | None = None
    direction_hint_period_s: float = 3.0
    max_direction_range_deg: float = 180.0
    min_direction_range_deg: float = 4.0
    stats_explanation: str = ""

    @field_validator("exactness", "direction_exactness", "distance_exactness")
    @classmethod
    def _validate_exactness(cls, value: float | None) -> float | None:
        if value is None:
            return None
        return _clamp_unit_interval(value, label="exactness")

    @field_validator("discovery_chance")
    @classmethod
    def _validate_discovery_chance(cls, value: float | None) -> float | None:
        if value is None:
            return None
        return _clamp_unit_interval(value, label="discovery_chance")

    @field_validator("duration_minutes")
    @classmethod
    def _validate_duration(cls, value: int) -> int:
        if value < 1:
            raise ValueError("duration_minutes must be >= 1")
        return value

    def resolved_direction_exactness(self) -> float:
        if self.direction_exactness is not None:
            return float(self.direction_exactness)
        if self.exactness is not None:
            return float(self.exactness)
        return 0.0

    def resolved_distance_exactness(self) -> float:
        if self.distance_exactness is not None:
            return float(self.distance_exactness)
        if self.exactness is not None:
            return float(self.exactness)
        return 0.0


class PeriodRgbColors(BaseModel):
    """RGB triple per geological period."""

    model_config = {"frozen": True}

    cretaceous: tuple[int, int, int]
    jurassic: tuple[int, int, int]
    triassic: tuple[int, int, int]

    @field_validator("cretaceous", "jurassic", "triassic", mode="before")
    @classmethod
    def _parse_rgb(cls, value: object) -> tuple[int, int, int]:
        return _parse_rgb_color(value)


class PeriodColorsConfig(BaseModel):
    """Site-marker and Orbit Survey overlay palettes (period_colors.yaml)."""

    model_config = {"frozen": True}

    site_markers: PeriodRgbColors
    orbit_survey: PeriodRgbColors


class RockTypeColorsConfig(BaseModel):
    """Formation Map rock-type overlay palettes (rock_type_colors.yaml)."""

    model_config = {"frozen": True}

    formation_map: dict[str, tuple[int, int, int]] = Field(default_factory=dict)

    @field_validator("formation_map", mode="before")
    @classmethod
    def _parse_formation_map(cls, value: object) -> dict[str, tuple[int, int, int]]:
        if not isinstance(value, dict):
            raise ValueError("formation_map rock colors must be a mapping")
        return {
            str(key).strip().lower(): _parse_rgb_color(color)
            for key, color in value.items()
        }

    def for_rock_type(self, rock_type: str | None) -> tuple[int, int, int]:
        key = (rock_type or "").strip().lower()
        if key and key in self.formation_map:
            return self.formation_map[key]
        return self.formation_map.get("other", (0x88, 0x88, 0x88))


class OrbitSurveyActionConfig(BaseModel):
    """Knobs for the Orbit Survey period-mosaic overlay."""

    model_config = {"frozen": True}

    duration_minutes: int = 10
    accuracy: float = 0.75
    range: float = 0.35
    min_range_m: float = 200.0
    max_range_m: float = 2000.0
    base_alpha: float = 0.48
    range_fade: float = 0.55
    boundary_blur: float = 0.7
    stats_explanation: str = ""

    @field_validator(
        "accuracy", "range", "base_alpha", "range_fade", "boundary_blur"
    )
    @classmethod
    def _validate_unit(cls, value: float) -> float:
        return _clamp_unit_interval(value, label="unit interval")

    @field_validator("duration_minutes")
    @classmethod
    def _validate_duration(cls, value: int) -> int:
        if value < 1:
            raise ValueError("duration_minutes must be >= 1")
        return value

    @field_validator("min_range_m", "max_range_m")
    @classmethod
    def _validate_range_m(cls, value: float) -> float:
        if value <= 0:
            raise ValueError("range meters must be > 0")
        return value

    @model_validator(mode="after")
    def _validate_range_bounds(self) -> OrbitSurveyActionConfig:
        if self.max_range_m < self.min_range_m:
            raise ValueError("max_range_m must be >= min_range_m")
        return self

    def resolved_range_m(self) -> float:
        return float(self.min_range_m) + float(self.range) * (
            float(self.max_range_m) - float(self.min_range_m)
        )


class FormationMapActionConfig(BaseModel):
    """Knobs for the Formation Map rock-type square mosaic."""

    model_config = {"frozen": True}

    duration_minutes: int = 10
    accuracy: float = 0.75
    wideness_m: float = 500.0
    min_wideness_m: float = 500.0
    max_wideness_m: float = 2000.0
    # Must match site_generation.lazy.cell_size_m (same fixed world grid).
    cell_size_m: float = 500.0
    base_alpha: float = 0.48
    range_fade: float = 0.0
    boundary_blur: float = 1.0
    stats_explanation: str = ""

    @field_validator("accuracy", "base_alpha", "range_fade", "boundary_blur")
    @classmethod
    def _validate_unit(cls, value: float) -> float:
        return _clamp_unit_interval(value, label="unit interval")

    @field_validator("duration_minutes")
    @classmethod
    def _validate_duration(cls, value: int) -> int:
        if value < 1:
            raise ValueError("duration_minutes must be >= 1")
        return value

    @field_validator(
        "wideness_m", "min_wideness_m", "max_wideness_m", "cell_size_m"
    )
    @classmethod
    def _validate_meters(cls, value: float) -> float:
        if value <= 0:
            raise ValueError("meters must be > 0")
        return value

    @model_validator(mode="after")
    def _validate_wideness_bounds(self) -> FormationMapActionConfig:
        if self.max_wideness_m < self.min_wideness_m:
            raise ValueError("max_wideness_m must be >= min_wideness_m")
        return self

    def resolved_wideness_m(self) -> float:
        cell = float(self.cell_size_m)
        lo = max(float(self.min_wideness_m), cell)
        hi = max(float(self.max_wideness_m), lo)
        raw = max(lo, min(hi, float(self.wideness_m)))
        n = max(1, int(round(raw / cell)))
        return float(n * cell)


def _parse_rgb_color(value: object) -> tuple[int, int, int]:
    if isinstance(value, str):
        raw = value.strip().lstrip("#")
        if len(raw) == 6:
            return (int(raw[0:2], 16), int(raw[2:4], 16), int(raw[4:6], 16))
        raise ValueError(f"color must be #RRGGBB, got {value!r}")
    if isinstance(value, (list, tuple)) and len(value) == 3:
        rgb = tuple(int(v) for v in value)
        if all(0 <= c <= 255 for c in rgb):
            return rgb  # type: ignore[return-value]
        raise ValueError(f"RGB channels must be 0–255, got {value!r}")
    raise ValueError(f"color must be #RRGGBB or [r,g,b], got {value!r}")


class LevelingSkillConfig(BaseModel):
    model_config = {"frozen": True}

    id: str
    name: str


class LevelingRewardsConfig(BaseModel):
    model_config = {"frozen": True}

    site_discover_site_discovery_xp: int = 10
    fossil_discover_fossil_detection_xp: int = 5
    active_km_site_discovery_xp: int = 30
    passive_km_site_discovery_xp: int = 5


class LevelingConfig(BaseModel):
    model_config = {"frozen": True}

    skills: tuple[LevelingSkillConfig, ...] = ()
    rewards: LevelingRewardsConfig = Field(default_factory=LevelingRewardsConfig)
    career_titles: tuple[str, ...] = ()

    @field_validator("skills", mode="before")
    @classmethod
    def _coerce_skills(cls, value: object) -> tuple[LevelingSkillConfig, ...]:
        if value is None:
            return ()
        if isinstance(value, (list, tuple)):
            return tuple(LevelingSkillConfig.model_validate(item) for item in value)
        raise ValueError("skills must be a sequence")

    @field_validator("career_titles", mode="before")
    @classmethod
    def _coerce_career_titles(cls, value: object) -> tuple[str, ...]:
        if value is None:
            return ()
        if isinstance(value, (list, tuple)):
            return tuple(str(item) for item in value)
        raise ValueError("career_titles must be a sequence of strings")

    @model_validator(mode="after")
    def _validate_leveling(self) -> LevelingConfig:
        if len(self.skills) < 1:
            raise ValueError("skills must have at least one entry")
        if len(self.career_titles) != 99:
            raise ValueError("career_titles must have exactly 99 entries")
        ids = [skill.id for skill in self.skills]
        if len(ids) != len(set(ids)):
            raise ValueError("skill ids must be unique")
        return self


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
    geo_compass: GuidanceActionConfig = Field(
        default_factory=lambda: GuidanceActionConfig(
            exactness=0.0,
            discovery_chance=0.9,
            duration_minutes=15,
            stats_explanation=(
                "Points toward the nearest undiscovered site for this duration; "
                "lower exactness adds needle drift."
            ),
        )
    )
    proximity_scanner: GuidanceActionConfig = Field(
        default_factory=lambda: GuidanceActionConfig(
            exactness=0.0,
            duration_minutes=15,
            discovery_chance=None,
            stats_explanation=(
                "Shows how far you are from the nearest undiscovered site."
            ),
        )
    )
    site_navigator: GuidanceActionConfig = Field(
        default_factory=lambda: GuidanceActionConfig(
            direction_exactness=0.0,
            distance_exactness=0.0,
            discovery_chance=0.9,
            duration_minutes=15,
            stats_explanation=(
                "Combines compass direction and proximity readout for the "
                "nearest undiscovered site."
            ),
        )
    )
    orbit_survey: OrbitSurveyActionConfig = Field(
        default_factory=lambda: OrbitSurveyActionConfig(
            duration_minutes=10,
            accuracy=0.75,
            range=0.35,
            min_range_m=200.0,
            max_range_m=2000.0,
            base_alpha=0.48,
            range_fade=0.55,
            boundary_blur=0.7,
            stats_explanation=(
                "Colors the map by the period of nearby undiscovered "
                "field sites. Higher accuracy sharpens boundaries; higher "
                "range widens the circle (200 m–2 km)."
            ),
        )
    )
    formation_map: FormationMapActionConfig = Field(
        default_factory=lambda: FormationMapActionConfig(
            duration_minutes=10,
            accuracy=0.75,
            wideness_m=200.0,
            min_wideness_m=200.0,
            max_wideness_m=2000.0,
            cell_size_m=200.0,
            base_alpha=0.48,
            range_fade=0.0,
            boundary_blur=1.0,
            stats_explanation=(
                "Colors a fixed square of the map by rock type. Higher "
                "accuracy sharpens boundaries; wideness sets the side "
                "length (200 m–2 km) of the square locked to this tool "
                "occurrence."
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
    period_colors: PeriodColorsConfig
    rock_type_colors: RockTypeColorsConfig
    leveling: LevelingConfig


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
        period_colors=PeriodColorsConfig.model_validate(
            _load_yaml(directory / "period_colors.yaml")
        ),
        rock_type_colors=RockTypeColorsConfig.model_validate(
            _load_yaml(directory / "rock_type_colors.yaml")
        ),
        leveling=LevelingConfig.model_validate(
            _load_yaml(directory / "leveling.yaml")
        ),
    )


@lru_cache(maxsize=1)
def get_game_config() -> GameConfig:
    """Process-wide singleton; clear with ``get_game_config.cache_clear()`` in tests."""
    return load_game_config()
