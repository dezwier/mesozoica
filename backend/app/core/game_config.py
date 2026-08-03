"""Load shared game-mechanics YAML (control board under app/game_config/)."""

from __future__ import annotations

import os
from functools import lru_cache
from pathlib import Path
from typing import Any, Literal

import yaml
from pydantic import BaseModel, Field, field_validator, model_validator

_PACKAGE_DIR = Path(__file__).resolve().parent
_DEFAULT_CONFIG_DIR = _PACKAGE_DIR.parent / "game_config"

# Numbered skill-domain YAML files (order matches leveling.yaml skills).
SKILL_YAML_FILES: tuple[tuple[str, str], ...] = (
    ("site_discovery", "01_site_discovery.yaml"),
    ("site_survey", "02_site_survey.yaml"),
    ("site_clearing", "03_site_clearing.yaml"),
    ("fossil_detection", "04_fossil_detection.yaml"),
    ("fossil_excavation", "05_fossil_excavation.yaml"),
    ("fossil_transport", "06_fossil_transport.yaml"),
    ("fossil_curation", "07_fossil_curation.yaml"),
    ("fossil_preparation", "08_fossil_preparation.yaml"),
    ("fossil_analysis", "09_fossil_analysis.yaml"),
    ("dinosaur_modelling", "10_dinosaur_modelling.yaml"),
    ("dinosaur_mounting", "11_dinosaur_mounting.yaml"),
    ("academic_publishing", "12_academic_publishing.yaml"),
)

ModifierOp = Literal["add", "multiply", "replace"]


def _load_yaml(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as handle:
        data = yaml.safe_load(handle)
    if data is None:
        return {}
    if not isinstance(data, dict):
        raise ValueError(f"Invalid game config (expected mapping): {path}")
    return data


def _weights_must_sum_to_one(weights: dict[Any, float], *, label: str) -> None:
    total = sum(weights.values())
    if abs(total - 1.0) > 1e-6:
        raise ValueError(f"{label} must sum to 1.0 (got {total})")


def _clamp_unit_interval(value: float, *, label: str) -> float:
    if value < 0.0 or value > 1.0:
        raise ValueError(f"{label} must be between 0.0 and 1.0")
    return value


# ---------------------------------------------------------------------------
# Shared modifier / skill stub models
# ---------------------------------------------------------------------------


class LevelModifierEntry(BaseModel):
    """Apply when skill level >= ``level`` (highest matching entry wins per param)."""

    model_config = {"frozen": True}

    level: int
    op: ModifierOp
    value: float

    @field_validator("level")
    @classmethod
    def _validate_level(cls, value: int) -> int:
        if value < 1:
            raise ValueError("level_modifiers level must be >= 1")
        return value


class ParamModifier(BaseModel):
    model_config = {"frozen": True}

    op: ModifierOp
    value: float


WeatherTimePeriod = Literal["dawn", "day", "dusk", "night"]
VALID_WEATHER_TIMES = frozenset({"dawn", "day", "dusk", "night"})
VALID_WEATHER_TYPES = frozenset(
    {
        "clear",
        "cloudy",
        "overcast",
        "fog",
        "drizzle",
        "rain",
        "snow",
        "thunderstorm",
        "hail",
        "unknown",
    }
)

# param_name → key (period or weather type) → ordered modifier list
WeatherTimeModifiers = dict[str, dict[str, list[ParamModifier]]]
WeatherTypeModifiers = dict[str, dict[str, list[ParamModifier]]]


def _coerce_keyed_param_modifiers(
    value: object,
    *,
    valid_keys: frozenset[str],
    label: str,
) -> dict[str, dict[str, list[ParamModifier]]]:
    if value is None:
        return {}
    if not isinstance(value, dict):
        raise ValueError(f"{label} must be a mapping")
    out: dict[str, dict[str, list[ParamModifier]]] = {}
    for param, keyed in value.items():
        if keyed is None:
            out[str(param)] = {}
            continue
        if not isinstance(keyed, dict):
            raise ValueError(f"{label}[{param}] must be a mapping")
        key_map: dict[str, list[ParamModifier]] = {}
        for raw_key, entries in keyed.items():
            key = str(raw_key).strip().lower()
            if key == "sunny":
                key = "clear"
            if key not in valid_keys:
                raise ValueError(f"unknown {label} key: {raw_key!r}")
            if entries is None:
                key_map[key] = []
            elif isinstance(entries, list):
                key_map[key] = [
                    ParamModifier.model_validate(item) for item in entries
                ]
            else:
                raise ValueError(f"{label}[{param}][{raw_key}] must be a list")
        out[str(param)] = key_map
    return out


def coerce_weather_time_modifiers(value: object) -> WeatherTimeModifiers:
    """Parse ``weather_time_modifiers`` YAML into param → period → mods."""
    return _coerce_keyed_param_modifiers(
        value, valid_keys=VALID_WEATHER_TIMES, label="weather_time_modifiers"
    )


def coerce_weather_type_modifiers(value: object) -> WeatherTypeModifiers:
    """Parse ``weather_type_modifiers`` YAML into param → weather type → mods."""
    return _coerce_keyed_param_modifiers(
        value, valid_keys=VALID_WEATHER_TYPES, label="weather_type_modifiers"
    )


ModifierWhen = Literal["using", "owning"]

# skill_id → param_name → modifier
SkillParamMods = dict[str, dict[str, ParamModifier]]


def _looks_like_param_modifier(value: object) -> bool:
    return isinstance(value, dict) and "op" in value and "value" in value


def _looks_like_param_map(value: object) -> bool:
    return isinstance(value, dict) and (
        not value or all(_looks_like_param_modifier(v) for v in value.values())
    )


def _coerce_param_modifier_map(value: object) -> dict[str, ParamModifier]:
    if value is None:
        return {}
    if not isinstance(value, dict):
        raise ValueError("modifier params must be a mapping")
    return {str(k): ParamModifier.model_validate(v) for k, v in value.items()}


def _coerce_skill_param_mods(value: object) -> SkillParamMods:
    if value is None:
        return {}
    if not isinstance(value, dict):
        raise ValueError("skill modifier map must be a mapping")
    out: SkillParamMods = {}
    for skill_id, params in value.items():
        out[str(skill_id)] = _coerce_param_modifier_map(params)
    return out


class ModifiesMainParams(BaseModel):
    """Tool impact on one or more skills' main_params.

    Preferred form (multi-skill; owning/using can differ)::

        owning:
          site_discovery: { discovery_chance: { op: add, value: 0.05 } }
          site_survey: { fossil_count: { op: multiply, value: 1.1 } }
        using:
          site_discovery: { discovery_chance: { op: replace, value: 0.9 } }

    Single-skill shorthand still accepted::

        skill: site_discovery
        using: { discovery_chance: { op: replace, value: 0.9 } }

    Legacy ``when`` + ``params`` also accepted.
    """

    model_config = {"frozen": True}

    owning: SkillParamMods = Field(default_factory=dict)
    using: SkillParamMods = Field(default_factory=dict)

    @model_validator(mode="before")
    @classmethod
    def _normalize_shapes(cls, value: object) -> object:
        if not isinstance(value, dict):
            return value
        data = dict(value)
        skill = data.pop("skill", None)

        # Legacy: when + params → owning/using param map.
        if "params" in data and ("owning" not in data and "using" not in data):
            when = str(data.pop("when", "using") or "using").strip().lower()
            params = data.pop("params") or {}
            if when == "owning":
                data["owning"] = params
            else:
                data["using"] = params

        # Single-skill shorthand: owning/using are param maps, not skill maps.
        if skill is not None:
            skill_id = str(skill)
            for key in ("owning", "using"):
                bucket = data.get(key)
                if _looks_like_param_map(bucket):
                    data[key] = {skill_id: bucket}
        return data

    @field_validator("owning", "using", mode="before")
    @classmethod
    def _coerce_buckets(cls, value: object) -> SkillParamMods:
        return _coerce_skill_param_mods(value)

    def params_for(
        self, when: ModifierWhen, skill_id: str
    ) -> dict[str, ParamModifier]:
        bucket = self.owning if when == "owning" else self.using
        return dict(bucket.get(skill_id, {}))

    def affects_skill(self, skill_id: str) -> bool:
        return skill_id in self.owning or skill_id in self.using

    def skill_ids(self) -> set[str]:
        return set(self.owning) | set(self.using)

    def entries(
        self,
    ) -> list[tuple[ModifierWhen, str, dict[str, ParamModifier]]]:
        """(when, skill_id, params) for each non-empty skill bucket."""
        out: list[tuple[ModifierWhen, str, dict[str, ParamModifier]]] = []
        for when, bucket in (("owning", self.owning), ("using", self.using)):
            for skill_id, params in bucket.items():
                if params:
                    out.append((when, skill_id, dict(params)))
        return out

    @property
    def has_any(self) -> bool:
        return bool(self.owning or self.using)


class SkillStubConfig(BaseModel):
    """Placeholder skill domain until main_params are defined."""

    model_config = {"frozen": True}

    skill_id: str
    enabled: bool = False
    main_params: dict[str, Any] = Field(default_factory=dict)
    level_modifiers: dict[str, list[LevelModifierEntry]] = Field(default_factory=dict)
    weather_time_modifiers: WeatherTimeModifiers = Field(default_factory=dict)
    weather_type_modifiers: WeatherTypeModifiers = Field(default_factory=dict)

    @field_validator("level_modifiers", mode="before")
    @classmethod
    def _coerce_level_modifiers(cls, value: object) -> dict[str, list]:
        if value is None:
            return {}
        if not isinstance(value, dict):
            raise ValueError("level_modifiers must be a mapping")
        return {str(k): (v if isinstance(v, list) else []) for k, v in value.items()}

    @field_validator("weather_time_modifiers", mode="before")
    @classmethod
    def _coerce_weather_time_modifiers(cls, value: object) -> WeatherTimeModifiers:
        return coerce_weather_time_modifiers(value)

    @field_validator("weather_type_modifiers", mode="before")
    @classmethod
    def _coerce_weather_type_modifiers(cls, value: object) -> WeatherTypeModifiers:
        return coerce_weather_type_modifiers(value)


# ---------------------------------------------------------------------------
# Site generation (not a skill)
# ---------------------------------------------------------------------------


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
# Skill 1 — Site Discovery
# ---------------------------------------------------------------------------


class SiteDiscoveryClientConfig(BaseModel):
    model_config = {"frozen": True}

    auto_discover_radius_m: float = 20.0
    cache_radius_km: float = 1.0
    cache_refresh_move_threshold_m: float = 500.0
    discover_fail_retry_s: int = 20
    discovery_reroll_interval_s: int = 10


class SiteDiscoveryMainParams(BaseModel):
    model_config = {"frozen": True}

    visibility_distance_m: float = 20.0
    discovery_chance: float = 0.1
    max_discovery_speed_kmh: float = 20.0

    @field_validator("discovery_chance")
    @classmethod
    def _validate_discovery_chance(cls, value: float) -> float:
        return _clamp_unit_interval(value, label="discovery_chance")

    @field_validator("visibility_distance_m", "max_discovery_speed_kmh")
    @classmethod
    def _validate_positive(cls, value: float) -> float:
        if value <= 0:
            raise ValueError("must be > 0")
        return value


class SiteDiscoveryConfig(BaseModel):
    model_config = {"frozen": True}

    skill_id: str = "site_discovery"
    main_params: SiteDiscoveryMainParams = Field(
        default_factory=SiteDiscoveryMainParams
    )
    level_modifiers: dict[str, list[LevelModifierEntry]] = Field(default_factory=dict)
    weather_time_modifiers: WeatherTimeModifiers = Field(default_factory=dict)
    weather_type_modifiers: WeatherTypeModifiers = Field(default_factory=dict)
    client: SiteDiscoveryClientConfig = Field(
        default_factory=SiteDiscoveryClientConfig
    )

    @field_validator("level_modifiers", mode="before")
    @classmethod
    def _coerce_level_modifiers(cls, value: object) -> dict[str, list]:
        if value is None:
            return {}
        if not isinstance(value, dict):
            raise ValueError("level_modifiers must be a mapping")
        return {str(k): (v if isinstance(v, list) else []) for k, v in value.items()}

    @field_validator("weather_time_modifiers", mode="before")
    @classmethod
    def _coerce_weather_time_modifiers(cls, value: object) -> WeatherTimeModifiers:
        return coerce_weather_time_modifiers(value)

    @field_validator("weather_type_modifiers", mode="before")
    @classmethod
    def _coerce_weather_type_modifiers(cls, value: object) -> WeatherTypeModifiers:
        return coerce_weather_type_modifiers(value)

    @property
    def visibility_distance_m(self) -> float:
        return float(self.main_params.visibility_distance_m)

    @property
    def discovery_chance(self) -> float:
        return float(self.main_params.discovery_chance)

    @property
    def max_discovery_speed_kmh(self) -> float:
        return float(self.main_params.max_discovery_speed_kmh)

    # Back-compat alias used by older call sites / tests.
    @property
    def max_distance_m(self) -> float:
        return self.visibility_distance_m


# ---------------------------------------------------------------------------
# Skill 2 — Site Survey (field fossil generation)
# ---------------------------------------------------------------------------


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
            raise ValueError("dino_count max_odd must be in [0, 1]")
        if self.count < 0:
            raise ValueError("dino_count count must be >= 0")
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


class SiteSurveyMainParams(BaseModel):
    model_config = {"frozen": True}

    # Site-card display precision for each odd_* axis (0 = blurry/jittered, 1 = exact).
    dino_accuracy: float = 0.0
    fossil_accuracy: float = 0.0
    completeness_accuracy: float = 0.0
    quality_accuracy: float = 0.0
    depth_accuracy: float = 0.0

    dino_count: list[DinoCountThreshold] = Field(
        default_factory=lambda: [
            DinoCountThreshold(max_odd=0.10, count=0),
            DinoCountThreshold(max_odd=0.60, count=1),
            DinoCountThreshold(max_odd=0.80, count=2),
            DinoCountThreshold(max_odd=0.90, count=3),
            DinoCountThreshold(max_odd=0.95, count=4),
            DinoCountThreshold(max_odd=1.00, count=5),
        ]
    )
    fossil_count: dict[int, float] = Field(
        default_factory=lambda: {
            1: 0.25,
            2: 0.25,
            3: 0.20,
            4: 0.15,
            5: 0.10,
            6: 0.05,
        }
    )
    depth_weights: list[FossilDepthBucket] = Field(
        default_factory=lambda: [
            FossilDepthBucket(weight=0.10, min_cm=0, max_cm=0),
            FossilDepthBucket(weight=0.30, min_cm=1, max_cm=50),
            FossilDepthBucket(weight=0.30, min_cm=51, max_cm=200),
            FossilDepthBucket(weight=0.20, min_cm=201, max_cm=500),
            FossilDepthBucket(weight=0.10, min_cm=501, max_cm=1000),
        ]
    )
    completeness_weights: dict[str, float] = Field(
        default_factory=lambda: {
            "trace_only": 0.05,
            "isolated_element": 0.20,
            "fragmentary": 0.30,
            "partial": 0.25,
            "substantial": 0.15,
            "nearly_complete": 0.05,
        }
    )
    quality_weights: dict[str, float] = Field(
        default_factory=lambda: {
            "very_poor": 0.05,
            "poor": 0.15,
            "moderate": 0.35,
            "good": 0.25,
            "excellent": 0.15,
            "exceptional": 0.05,
        }
    )

    @field_validator(
        "dino_accuracy",
        "fossil_accuracy",
        "completeness_accuracy",
        "quality_accuracy",
        "depth_accuracy",
    )
    @classmethod
    def _validate_accuracy(cls, value: float) -> float:
        return _clamp_unit_interval(value, label="accuracy")

    @field_validator("fossil_count", mode="before")
    @classmethod
    def _coerce_int_keys(cls, value: Any) -> dict[int, float]:
        if not isinstance(value, dict):
            raise TypeError("fossil_count must be a mapping")
        return {int(k): float(v) for k, v in value.items()}

    @field_validator("completeness_weights", "quality_weights", mode="before")
    @classmethod
    def _coerce_str_weights(cls, value: Any) -> dict[str, float]:
        if not isinstance(value, dict):
            raise TypeError("weights must be a mapping")
        return {str(k): float(v) for k, v in value.items()}

    @model_validator(mode="after")
    def _validate_weights(self) -> SiteSurveyMainParams:
        if not self.dino_count:
            raise ValueError("dino_count must not be empty")
        prev = -1.0
        for threshold in self.dino_count:
            if threshold.max_odd < prev:
                raise ValueError("dino_count must be ordered by max_odd")
            prev = threshold.max_odd
        if abs(self.dino_count[-1].max_odd - 1.0) > 1e-6:
            raise ValueError("dino_count final max_odd must be 1.0")
        _weights_must_sum_to_one(self.fossil_count, label="fossil_count")
        if not self.depth_weights:
            raise ValueError("depth_weights must not be empty")
        total = sum(bucket.weight for bucket in self.depth_weights)
        if abs(total - 1.0) > 1e-6:
            raise ValueError(f"depth_weights weights must sum to 1.0 (got {total})")
        _weights_must_sum_to_one(
            self.completeness_weights, label="completeness_weights"
        )
        _weights_must_sum_to_one(self.quality_weights, label="quality_weights")
        return self


class SiteSurveyConfig(BaseModel):
    """Field fossil spawn knobs for the Site Survey skill."""

    model_config = {"frozen": True}

    skill_id: str = "site_survey"
    main_params: SiteSurveyMainParams = Field(default_factory=SiteSurveyMainParams)
    level_modifiers: dict[str, list[LevelModifierEntry]] = Field(default_factory=dict)
    weather_time_modifiers: WeatherTimeModifiers = Field(default_factory=dict)
    weather_type_modifiers: WeatherTypeModifiers = Field(default_factory=dict)
    odd_noise: FossilOddNoiseConfig = Field(default_factory=FossilOddNoiseConfig)
    defaults: FossilGenerationDefaults = Field(
        default_factory=FossilGenerationDefaults
    )

    @field_validator("level_modifiers", mode="before")
    @classmethod
    def _coerce_level_modifiers(cls, value: object) -> dict[str, list]:
        if value is None:
            return {}
        if not isinstance(value, dict):
            raise ValueError("level_modifiers must be a mapping")
        return {str(k): (v if isinstance(v, list) else []) for k, v in value.items()}

    @field_validator("weather_time_modifiers", mode="before")
    @classmethod
    def _coerce_weather_time_modifiers(cls, value: object) -> WeatherTimeModifiers:
        return coerce_weather_time_modifiers(value)

    @field_validator("weather_type_modifiers", mode="before")
    @classmethod
    def _coerce_weather_type_modifiers(cls, value: object) -> WeatherTypeModifiers:
        return coerce_weather_type_modifiers(value)

    @property
    def dino_count(self) -> list[DinoCountThreshold]:
        return list(self.main_params.dino_count)

    @property
    def fossil_count(self) -> dict[int, float]:
        return dict(self.main_params.fossil_count)

    @property
    def depth_weights(self) -> list[FossilDepthBucket]:
        return list(self.main_params.depth_weights)

    @property
    def completeness_weights(self) -> dict[str, float]:
        return dict(self.main_params.completeness_weights)

    @property
    def quality_weights(self) -> dict[str, float]:
        return dict(self.main_params.quality_weights)

    # Back-compat aliases for call sites / tests during migration.
    @property
    def dino_count_thresholds(self) -> list[DinoCountThreshold]:
        return self.dino_count

    @property
    def card_count_weights(self) -> dict[int, float]:
        return self.fossil_count

    @property
    def depth_buckets(self) -> list[FossilDepthBucket]:
        return self.depth_weights


# Back-compat alias.
FossilGenerationConfig = SiteSurveyConfig


# ---------------------------------------------------------------------------
# Tool actions
# ---------------------------------------------------------------------------


class AerialActionConfig(BaseModel):
    model_config = {"frozen": True}

    duration_minutes: int = 60
    loop_endpoint_tolerance_m: float = 75.0
    flight_speed_kmh: float = 50.0
    flight_discovery_chance: float = 0.2
    flight_discovery_distance_m: float = 200.0
    ensure_timeout_s: int = 600
    short_route_warn_fraction: float = 0.7
    stats_explanation: str = (
        "Duration caps how far you can draw (speed × duration). Flight time is "
        "drawn length ÷ speed. Sites within flight discovery distance are rolled "
        "at the listed chance."
    )

    @property
    def max_route_km(self) -> float:
        """Derived draw/deploy limit: speed × duration."""
        return float(self.flight_speed_kmh) * float(self.duration_minutes) / 60.0

    @field_validator("duration_minutes")
    @classmethod
    def _validate_duration(cls, value: int) -> int:
        if value < 1:
            raise ValueError("duration_minutes must be >= 1")
        return value

    @field_validator("flight_discovery_chance")
    @classmethod
    def _validate_flight_discovery_chance(cls, value: float) -> float:
        return _clamp_unit_interval(value, label="flight_discovery_chance")

    @field_validator("short_route_warn_fraction")
    @classmethod
    def _validate_short_route_warn_fraction(cls, value: float) -> float:
        return _clamp_unit_interval(value, label="short_route_warn_fraction")


# Back-compat alias for older imports/tests.
AerialReconActionConfig = AerialActionConfig


class GuidanceActionConfig(BaseModel):
    """Knobs for site-guidance tools (compass / proximity / navigator)."""

    model_config = {"frozen": True}

    duration_minutes: int = 15
    # Single-axis tools (geo_compass direction, proximity_scanner distance).
    exactness: float | None = None
    # Site navigator dual axes.
    direction_exactness: float | None = None
    distance_exactness: float | None = None
    modifies_main_params: ModifiesMainParams | None = None
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

    @property
    def discovery_chance(self) -> float | None:
        """Walk-in discovery_chance from using/site_discovery modifiers."""
        mods = self.modifies_main_params
        if mods is None:
            return None
        mod = mods.params_for("using", "site_discovery").get("discovery_chance")
        if mod is None:
            return None
        return float(mod.value)


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


class TerrainEchoActionConfig(BaseModel):
    """Knobs for the Terrain Echo vintage radar overlay."""

    model_config = {"frozen": True}

    accuracy: float = 0.0
    range_m: float = 20.0
    min_range_m: float = 20.0
    max_range_m: float = 200.0
    duration_minutes: int = 5
    min_duration_minutes: int = 5
    max_duration_minutes: int = 20
    ring_increment_m: float = 20.0
    sweep_period_s: float = 4.0
    stats_explanation: str = ""

    @field_validator("accuracy")
    @classmethod
    def _validate_accuracy(cls, value: float) -> float:
        return _clamp_unit_interval(value, label="accuracy")

    @field_validator(
        "range_m",
        "min_range_m",
        "max_range_m",
        "ring_increment_m",
        "sweep_period_s",
    )
    @classmethod
    def _validate_positive(cls, value: float) -> float:
        if value <= 0:
            raise ValueError("value must be > 0")
        return value

    @field_validator(
        "duration_minutes", "min_duration_minutes", "max_duration_minutes"
    )
    @classmethod
    def _validate_duration(cls, value: int) -> int:
        if value < 1:
            raise ValueError("duration_minutes must be >= 1")
        return value

    @model_validator(mode="after")
    def _validate_bounds(self) -> TerrainEchoActionConfig:
        if self.max_range_m < self.min_range_m:
            raise ValueError("max_range_m must be >= min_range_m")
        if self.max_duration_minutes < self.min_duration_minutes:
            raise ValueError(
                "max_duration_minutes must be >= min_duration_minutes"
            )
        if not (self.min_range_m <= self.range_m <= self.max_range_m):
            raise ValueError("range_m must be within min/max_range_m")
        if not (
            self.min_duration_minutes
            <= self.duration_minutes
            <= self.max_duration_minutes
        ):
            raise ValueError(
                "duration_minutes must be within min/max_duration_minutes"
            )
        return self


class RidgeGlassActionConfig(BaseModel):
    """Knobs for Ridge Glass walk-in visibility / discovery buffs."""

    model_config = {"frozen": True}

    duration_minutes: int = 60
    modifies_main_params: ModifiesMainParams | None = None
    stats_explanation: str = ""

    @field_validator("duration_minutes")
    @classmethod
    def _validate_duration(cls, value: int) -> int:
        if value < 1:
            raise ValueError("duration_minutes must be >= 1")
        return value

    def _using_site_discovery_mod(self, param: str) -> ParamModifier | None:
        mods = self.modifies_main_params
        if mods is None:
            return None
        return mods.params_for("using", "site_discovery").get(param)

    def site_discovery_mod(self, param: str) -> ParamModifier | None:
        """Active ``using`` / ``site_discovery`` modifier for ``param``, if any."""
        return self._using_site_discovery_mod(param)

    @property
    def added_visibility_range_m(self) -> float | None:
        mod = self._using_site_discovery_mod("visibility_distance_m")
        if mod is None or mod.op != "add":
            return None
        return float(mod.value)

    @property
    def added_discovery_rate(self) -> float | None:
        mod = self._using_site_discovery_mod("discovery_chance")
        if mod is None or mod.op != "add":
            return None
        return float(mod.value)


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

    aerial_recon: AerialActionConfig = Field(
        default_factory=AerialActionConfig
    )
    aerial_scout: AerialActionConfig = Field(
        default_factory=lambda: AerialActionConfig(
            duration_minutes=10,
            flight_speed_kmh=35.0,
            flight_discovery_chance=0.008,
            flight_discovery_distance_m=50.0,
            stats_explanation=(
                "Duration caps how far you can draw (speed × duration). Flight time is "
                "drawn length ÷ speed. Sites within flight discovery distance are "
                "rolled at the listed chance."
            ),
        )
    )
    geo_compass: GuidanceActionConfig = Field(
        default_factory=lambda: GuidanceActionConfig(
            exactness=0.0,
            duration_minutes=15,
            modifies_main_params=ModifiesMainParams(
                using={
                    "site_discovery": {
                        "discovery_chance": ParamModifier(op="replace", value=0.9),
                    }
                },
            ),
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
            modifies_main_params=None,
            stats_explanation=(
                "Shows how far you are from the nearest undiscovered site."
            ),
        )
    )
    site_navigator: GuidanceActionConfig = Field(
        default_factory=lambda: GuidanceActionConfig(
            direction_exactness=0.0,
            distance_exactness=0.0,
            duration_minutes=15,
            modifies_main_params=ModifiesMainParams(
                using={
                    "site_discovery": {
                        "discovery_chance": ParamModifier(op="replace", value=0.9),
                    }
                },
            ),
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
    terrain_echo: TerrainEchoActionConfig = Field(
        default_factory=lambda: TerrainEchoActionConfig(
            accuracy=0.0,
            range_m=20.0,
            min_range_m=20.0,
            max_range_m=200.0,
            duration_minutes=5,
            min_duration_minutes=5,
            max_duration_minutes=20,
            ring_increment_m=20.0,
            sweep_period_s=4.0,
            stats_explanation=(
                "Rotating survey pulse around your position. Blips mark "
                "nearby sites you have not discovered yet. Higher accuracy "
                "tightens blips; range sets pulse radius (20–200 m)."
            ),
        )
    )
    ridge_glass: RidgeGlassActionConfig = Field(
        default_factory=lambda: RidgeGlassActionConfig(
            duration_minutes=60,
            modifies_main_params=ModifiesMainParams(
                using={
                    "site_discovery": {
                        "visibility_distance_m": ParamModifier(
                            op="multiply", value=1.3
                        ),
                        "discovery_chance": ParamModifier(
                            op="multiply", value=1.3
                        ),
                    }
                },
            ),
            stats_explanation=(
                "While active, multiplies site visibility range and walk-in "
                "discovery chance by 1.3 for all sites."
            ),
        )
    )

    def guidance_config_for(self, action_key: str) -> GuidanceActionConfig:
        mapping = {
            "geo_compass": self.geo_compass,
            "proximity_scanner": self.proximity_scanner,
            "site_navigator": self.site_navigator,
        }
        try:
            return mapping[action_key]
        except KeyError as exc:
            raise KeyError(f"unknown guidance action: {action_key}") from exc

    def tools_modifying_skill(self, skill_id: str) -> list[tuple[str, ModifiesMainParams]]:
        """Return (action_key, mods) for tools that modify ``skill_id``."""
        out: list[tuple[str, ModifiesMainParams]] = []
        for key, cfg in (
            ("geo_compass", self.geo_compass),
            ("proximity_scanner", self.proximity_scanner),
            ("site_navigator", self.site_navigator),
            ("ridge_glass", self.ridge_glass),
        ):
            mods = cfg.modifies_main_params
            if mods is not None and mods.affects_skill(skill_id):
                out.append((key, mods))
        return out


class GameConfig(BaseModel):
    model_config = {"frozen": True}

    site_generation: SiteGenerationConfig
    site_discovery: SiteDiscoveryConfig
    site_survey: SiteSurveyConfig
    site_clearing: SkillStubConfig
    fossil_detection: SkillStubConfig
    fossil_excavation: SkillStubConfig
    fossil_transport: SkillStubConfig
    fossil_curation: SkillStubConfig
    fossil_preparation: SkillStubConfig
    fossil_analysis: SkillStubConfig
    dinosaur_modelling: SkillStubConfig
    dinosaur_mounting: SkillStubConfig
    academic_publishing: SkillStubConfig
    tool_actions: ToolActionsConfig
    period_colors: PeriodColorsConfig
    rock_type_colors: RockTypeColorsConfig
    leveling: LevelingConfig

    # Back-compat aliases.
    @property
    def fossil_generation(self) -> SiteSurveyConfig:
        return self.site_survey

    @property
    def fossil_discovery(self) -> SkillStubConfig:
        return self.fossil_detection

    def skill_domain(self, skill_id: str) -> Any:
        """Return the config object for a skill id (rich or stub)."""
        mapping: dict[str, Any] = {
            "site_discovery": self.site_discovery,
            "site_survey": self.site_survey,
            "site_clearing": self.site_clearing,
            "fossil_detection": self.fossil_detection,
            "fossil_excavation": self.fossil_excavation,
            "fossil_transport": self.fossil_transport,
            "fossil_curation": self.fossil_curation,
            "fossil_preparation": self.fossil_preparation,
            "fossil_analysis": self.fossil_analysis,
            "dinosaur_modelling": self.dinosaur_modelling,
            "dinosaur_mounting": self.dinosaur_mounting,
            "academic_publishing": self.academic_publishing,
        }
        try:
            return mapping[skill_id]
        except KeyError as exc:
            raise KeyError(f"unknown skill id: {skill_id}") from exc


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

    skill_raw: dict[str, dict[str, Any]] = {}
    for skill_id, filename in SKILL_YAML_FILES:
        skill_raw[skill_id] = _load_yaml(directory / filename)

    return GameConfig(
        site_generation=SiteGenerationConfig.model_validate(
            _load_yaml(directory / "site_generation.yaml")
        ),
        site_discovery=SiteDiscoveryConfig.model_validate(
            skill_raw["site_discovery"]
        ),
        site_survey=SiteSurveyConfig.model_validate(skill_raw["site_survey"]),
        site_clearing=SkillStubConfig.model_validate(skill_raw["site_clearing"]),
        fossil_detection=SkillStubConfig.model_validate(
            skill_raw["fossil_detection"]
        ),
        fossil_excavation=SkillStubConfig.model_validate(
            skill_raw["fossil_excavation"]
        ),
        fossil_transport=SkillStubConfig.model_validate(
            skill_raw["fossil_transport"]
        ),
        fossil_curation=SkillStubConfig.model_validate(skill_raw["fossil_curation"]),
        fossil_preparation=SkillStubConfig.model_validate(
            skill_raw["fossil_preparation"]
        ),
        fossil_analysis=SkillStubConfig.model_validate(skill_raw["fossil_analysis"]),
        dinosaur_modelling=SkillStubConfig.model_validate(
            skill_raw["dinosaur_modelling"]
        ),
        dinosaur_mounting=SkillStubConfig.model_validate(
            skill_raw["dinosaur_mounting"]
        ),
        academic_publishing=SkillStubConfig.model_validate(
            skill_raw["academic_publishing"]
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
