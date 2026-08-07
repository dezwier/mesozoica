"""Shared skill modifier and stub models."""

from __future__ import annotations

from typing import Any, Literal

from pydantic import BaseModel, Field, field_validator, model_validator

ModifierOp = Literal["add", "multiply", "replace"]

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
    """Keyframe for skill-level scaling.

    Resolution linearly interpolates ``value`` between adjacent keyframes
    (same ``op``). Below the first keyframe is identity; at/above the last
    uses that entry. Sparse endpoints (e.g. L1 + L99) are enough for a
    linear ramp.
    """

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


WeatherTimePeriod = Literal["dawn", "day", "dusk", "golden_hour", "night"]
VALID_WEATHER_TIMES = frozenset({"dawn", "day", "dusk", "golden_hour", "night"})
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
          site_stewardship: { document_accuracy: { op: add, value: 0.1 } }
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


