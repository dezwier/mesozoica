"""Typed field_survey document models."""

from __future__ import annotations

from typing import Any

from pydantic import BaseModel, Field, field_validator, model_validator

from app.features.game_config.sections.modifiers import (
    LevelModifierEntry,
    SkillStubConfig,
    WeatherTimeModifiers,
    WeatherTypeModifiers,
    _clamp_unit_interval,
    _weights_must_sum_to_one,
    coerce_weather_time_modifiers,
    coerce_weather_type_modifiers,
)

class FieldSurveyClientConfig(BaseModel):
    model_config = {"frozen": True}

    auto_discover_radius_m: float = 20.0
    cache_radius_km: float = 1.0
    cache_refresh_move_threshold_m: float = 500.0
    discover_fail_retry_s: int = 20
    discovery_reroll_interval_s: int = 10


class FieldSurveyMainParams(BaseModel):
    """Player-facing Field Survey knobs (level / weather / tool resolvable)."""

    model_config = {"frozen": True}

    # Discovery
    visibility_distance_m: float = 20.0
    discovery_chance: float = 0.1
    discovery_max_speed_kmh: float = 10.0
    discover_site_xp: float = 20.0
    discover_site_as_first_xp: float = 20.0
    explore_100m_actively_xp: float = 20.0
    explore_100m_passively_xp: float = 10.0
    # Stewardship / documentation
    document_accuracy: float = 0.01
    rival_discovery_chance: float = 1.0
    document_speed: float = 0.01
    disguise_of_site_xp: float = 40.0
    document_site_xp: float = 80.0
    document_site_as_first_xp: float = 20.0
    identify_site_xp: float = 40.0

    @field_validator("discovery_chance")
    @classmethod
    def _validate_discovery_chance(cls, value: float) -> float:
        return _clamp_unit_interval(value, label="discovery_chance")

    @field_validator(
        "visibility_distance_m",
        "discovery_max_speed_kmh",
        "discover_site_xp",
        "discover_site_as_first_xp",
        "explore_100m_actively_xp",
        "explore_100m_passively_xp",
    )
    @classmethod
    def _validate_positive(cls, value: float) -> float:
        if value <= 0:
            raise ValueError("must be > 0")
        return value

    @field_validator("document_accuracy")
    @classmethod
    def _validate_accuracy(cls, value: float) -> float:
        return _clamp_unit_interval(value, label="document_accuracy")

    @field_validator("rival_discovery_chance")
    @classmethod
    def _validate_rival_discovery(cls, value: float) -> float:
        if value < 0.0:
            raise ValueError("rival_discovery_chance must be >= 0")
        return value

    @field_validator("document_speed")
    @classmethod
    def _validate_documentation_distance(cls, value: float) -> float:
        if value < 0.0:
            raise ValueError("documentation parameters must be >= 0")
        return value

    @field_validator(
        "disguise_of_site_xp",
        "document_site_xp",
        "document_site_as_first_xp",
        "identify_site_xp",
    )
    @classmethod
    def _validate_xp(cls, value: float) -> float:
        if value < 0.0:
            raise ValueError("XP main_params must be >= 0")
        return value


# Back-compat aliases for param/client types.
SiteDiscoveryClientConfig = FieldSurveyClientConfig
SiteDiscoveryMainParams = FieldSurveyMainParams
SiteStewardshipMainParams = FieldSurveyMainParams


# ---------------------------------------------------------------------------
# Field fossil generation helpers (tables live on Field Survey)
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


class AccuracyNoiseConfig(BaseModel):
    """Stable per-axis jitter around skill baseline accuracy (display-only)."""

    model_config = {"frozen": True}

    # Absolute half-amplitude (± accuracy points on [0, 1]), independent of baseline.
    max_delta: float = 0.30

    @field_validator("max_delta")
    @classmethod
    def _validate_non_negative(cls, value: float) -> float:
        if value < 0.0:
            raise ValueError("accuracy_noise.max_delta must be >= 0")
        return value


class FieldSurveyConfig(BaseModel):
    """Field Survey skill: discovery, stewardship, and field fossil spawn tables."""

    model_config = {"frozen": True}

    skill_id: str = "field_survey"
    main_params: FieldSurveyMainParams = Field(default_factory=FieldSurveyMainParams)
    client: FieldSurveyClientConfig = Field(default_factory=FieldSurveyClientConfig)
    # Fixed global distribution tables (not subject to level/tool multipliers).
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
    level_modifiers: dict[str, list[LevelModifierEntry]] = Field(default_factory=dict)
    weather_time_modifiers: WeatherTimeModifiers = Field(default_factory=dict)
    weather_type_modifiers: WeatherTypeModifiers = Field(default_factory=dict)
    odd_noise: FossilOddNoiseConfig = Field(default_factory=FossilOddNoiseConfig)
    accuracy_noise: AccuracyNoiseConfig = Field(default_factory=AccuracyNoiseConfig)
    defaults: FossilGenerationDefaults = Field(
        default_factory=FossilGenerationDefaults
    )

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
    def _validate_distributions(self) -> FieldSurveyConfig:
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
    def dino_count_thresholds(self) -> list[DinoCountThreshold]:
        return list(self.dino_count)

    @property
    def card_count_weights(self) -> dict[int, float]:
        return dict(self.fossil_count)

    @property
    def depth_buckets(self) -> list[FossilDepthBucket]:
        return list(self.depth_weights)

    @property
    def visibility_distance_m(self) -> float:
        return float(self.main_params.visibility_distance_m)

    @property
    def discovery_chance(self) -> float:
        return float(self.main_params.discovery_chance)

    @property
    def discovery_max_speed_kmh(self) -> float:
        return float(self.main_params.discovery_max_speed_kmh)

    @property
    def discover_site_xp(self) -> float:
        return float(self.main_params.discover_site_xp)

    @property
    def discover_site_as_first_xp(self) -> float:
        return float(self.main_params.discover_site_as_first_xp)

    @property
    def explore_100m_actively_xp(self) -> float:
        return float(self.main_params.explore_100m_actively_xp)

    @property
    def explore_100m_passively_xp(self) -> float:
        return float(self.main_params.explore_100m_passively_xp)

    @property
    def disguise_of_site_xp(self) -> float:
        return float(self.main_params.disguise_of_site_xp)

    @property
    def document_site_xp(self) -> float:
        return float(self.main_params.document_site_xp)

    @property
    def document_site_as_first_xp(self) -> float:
        return float(self.main_params.document_site_as_first_xp)

    @property
    def identify_site_xp(self) -> float:
        return float(self.main_params.identify_site_xp)

    @property
    def document_speed(self) -> float:
        return float(self.main_params.document_speed)

    @property
    def rival_discovery_chance(self) -> float:
        return float(self.main_params.rival_discovery_chance)


# Back-compat aliases.
SiteDiscoveryConfig = FieldSurveyConfig
SiteStewardshipConfig = FieldSurveyConfig
FossilGenerationConfig = FieldSurveyConfig


# ---------------------------------------------------------------------------
# Tool actions
# ---------------------------------------------------------------------------
