"""Typed tool-action section models."""

from __future__ import annotations

from pydantic import BaseModel, Field, field_validator, model_validator

from app.features.game_config.sections.modifiers import (
    ModifiesMainParams,
    ParamModifier,
    VALID_WEATHER_TIMES,
    WeatherTimePeriod,
    _clamp_unit_interval,
)

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
        mod = mods.params_for("using", "field_survey").get("discovery_chance")
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


class MainParamBuffActionConfig(BaseModel):
    """Knobs for timed global main-param buffs (Ridge Glass, Drivetrain, Nocturne).

    When ``active_weather_times`` is set, the session may only start in those
    solar periods and is auto-stopped when the period leaves the list.
    """

    model_config = {"frozen": True}

    duration_minutes: int = 60
    modifies_main_params: ModifiesMainParams | None = None
    # None = always active; e.g. ["night"] for Nocturne Lens.
    active_weather_times: tuple[WeatherTimePeriod, ...] | None = None
    stats_explanation: str = ""

    @field_validator("duration_minutes")
    @classmethod
    def _validate_duration(cls, value: int) -> int:
        if value < 1:
            raise ValueError("duration_minutes must be >= 1")
        return value

    @field_validator("active_weather_times", mode="before")
    @classmethod
    def _coerce_active_weather_times(
        cls, value: object
    ) -> tuple[WeatherTimePeriod, ...] | None:
        if value is None:
            return None
        if isinstance(value, (list, tuple)):
            out: list[WeatherTimePeriod] = []
            for item in value:
                key = str(item)
                if key not in VALID_WEATHER_TIMES:
                    raise ValueError(
                        f"active_weather_times entry must be one of "
                        f"{sorted(VALID_WEATHER_TIMES)}, got {key!r}"
                    )
                out.append(key)  # type: ignore[arg-type]
            if not out:
                raise ValueError("active_weather_times must not be empty when set")
            return tuple(out)
        raise ValueError("active_weather_times must be a sequence or null")

    def _using_site_discovery_mod(self, param: str) -> ParamModifier | None:
        mods = self.modifies_main_params
        if mods is None:
            return None
        return mods.params_for("using", "field_survey").get(param)

    def site_discovery_mod(self, param: str) -> ParamModifier | None:
        """Active ``using`` / ``field_survey`` modifier for ``param``, if any."""
        return self._using_site_discovery_mod(param)

    def is_active_for_weather_time(self, weather_time: str | None) -> bool:
        """True when buff mods apply for ``weather_time`` (always if unrestricted)."""
        allowed = self.active_weather_times
        if allowed is None:
            return True
        if weather_time is None:
            return False
        return weather_time in allowed

    @property
    def added_visibility_range_m(self) -> float | None:
        mod = self._using_site_discovery_mod("discovery_distance_m")
        if mod is None or mod.op != "add":
            return None
        return float(mod.value)

    @property
    def added_discovery_rate(self) -> float | None:
        mod = self._using_site_discovery_mod("discovery_chance")
        if mod is None or mod.op != "add":
            return None
        return float(mod.value)


# Back-compat alias for older imports / tests.
RidgeGlassActionConfig = MainParamBuffActionConfig


class DisguiseActionConfig(BaseModel):
    """Knobs for site-stewardship disguise covers (Brush Scrim / Blackout Cover)."""

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

    def site_stewardship_mod(self, param: str) -> ParamModifier | None:
        mods = self.modifies_main_params
        if mods is None:
            return None
        return mods.params_for("using", "field_survey").get(param)

    @property
    def rival_discovery_mod(self) -> ParamModifier | None:
        return self.site_stewardship_mod("rival_discovery_chance")


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
