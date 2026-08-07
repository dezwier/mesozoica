"""Composition model for the tool_actions document."""

from __future__ import annotations

from pydantic import BaseModel, Field

from app.features.game_config.sections.actions import *  # noqa: F403
from app.features.game_config.sections.modifiers import *  # noqa: F403

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
                "drawn length ÷ speed. Sites within flight visibility distance are "
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
                    "field_survey": {
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
                    "field_survey": {
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
    ridge_glass: MainParamBuffActionConfig = Field(
        default_factory=lambda: MainParamBuffActionConfig(
            duration_minutes=60,
            modifies_main_params=ModifiesMainParams(
                using={
                    "field_survey": {
                        "visibility_distance_m": ParamModifier(
                            op="multiply", value=1.3
                        ),
                        "discovery_chance": ParamModifier(
                            op="multiply", value=1.3
                        ),
                        "discovery_max_speed_kmh": ParamModifier(
                            op="multiply", value=0.7
                        ),
                    }
                },
            ),
            stats_explanation=(
                "While active, boosts site visibility range and walk-in "
                "discovery chance, and decreases max discovery speed for all sites."
            ),
        )
    )
    trail_striders: MainParamBuffActionConfig = Field(
        default_factory=lambda: MainParamBuffActionConfig(
            duration_minutes=60,
            modifies_main_params=ModifiesMainParams(
                using={
                    "field_survey": {
"visibility_distance_m": ParamModifier(
                            op="multiply", value=0.95
                        ),
                        "discovery_chance": ParamModifier(
                            op="multiply", value=0.95
                        ),
                        "discovery_max_speed_kmh": ParamModifier(
                            op="multiply", value=2.0
                        ),
                    },
                },
            ),
            stats_explanation=(
                "While active, raises max discovery speed by 100% so a fast jog "
                "still counts toward visibility distance, but discover "
                "visibility, walk-in chance, and site exploration radius drop 5%."
            ),
        )
    )
    # Same shape as Ridge Glass (duration + modifies_main_params).
    expedition_drivetrain: MainParamBuffActionConfig = Field(
        default_factory=lambda: MainParamBuffActionConfig(
            duration_minutes=60,
            modifies_main_params=ModifiesMainParams(
                using={
                    "field_survey": {
"visibility_distance_m": ParamModifier(
                            op="multiply", value=0.9
                        ),
                        "discovery_chance": ParamModifier(
                            op="multiply", value=0.9
                        ),
                        "discovery_max_speed_kmh": ParamModifier(
                            op="multiply", value=3.0
                        ),
                    },
                },
            ),
            stats_explanation=(
                "While active, raises max discovery speed by 200% so bicycle "
                "travel still counts toward visibility distance, but discover "
                "visibility, walk-in chance, and site exploration radius drop 10%."
            ),
        )
    )
    canyon_throttle: MainParamBuffActionConfig = Field(
        default_factory=lambda: MainParamBuffActionConfig(
            duration_minutes=60,
            modifies_main_params=ModifiesMainParams(
                using={
                    "field_survey": {
"visibility_distance_m": ParamModifier(
                            op="multiply", value=0.85
                        ),
                        "discovery_chance": ParamModifier(
                            op="multiply", value=0.85
                        ),
                        "discovery_max_speed_kmh": ParamModifier(
                            op="multiply", value=4.0
                        ),
                    },
                },
            ),
            stats_explanation=(
                "While active, raises max discovery speed by 300% so motorcycle "
                "travel still counts toward visibility distance, but discover "
                "visibility, walk-in chance, and site exploration radius drop 15%."
            ),
        )
    )
    overland_chassis: MainParamBuffActionConfig = Field(
        default_factory=lambda: MainParamBuffActionConfig(
            duration_minutes=60,
            modifies_main_params=ModifiesMainParams(
                using={
                    "field_survey": {
"visibility_distance_m": ParamModifier(
                            op="multiply", value=0.8
                        ),
                        "discovery_chance": ParamModifier(
                            op="multiply", value=0.8
                        ),
                        "discovery_max_speed_kmh": ParamModifier(
                            op="multiply", value=5.0
                        ),
                    },
                },
            ),
            stats_explanation=(
                "While active, raises max discovery speed by 400% so 4x4 travel "
                "still counts toward visibility distance, but discover "
                "visibility, walk-in chance, and site exploration radius drop 20%."
            ),
        )
    )
    nocturne_lens: MainParamBuffActionConfig = Field(
        default_factory=lambda: MainParamBuffActionConfig(
            duration_minutes=60,
            active_weather_times=("night",),
            modifies_main_params=ModifiesMainParams(
                using={
                    "field_survey": {
                        "visibility_distance_m": ParamModifier(
                            op="multiply", value=1.4
                        ),
                        "discovery_chance": ParamModifier(
                            op="multiply", value=1.4
                        ),
                    }
                },
            ),
            stats_explanation=(
                "Lifetime battery; only starts and runs at night. Boosts "
                "visibility range and walk-in discovery chance by 40%. Stops "
                "automatically when night ends (dawn / day / dusk)."
            ),
        )
    )
    brush_scrim: DisguiseActionConfig = Field(
        default_factory=lambda: DisguiseActionConfig(
            duration_minutes=60,
            modifies_main_params=ModifiesMainParams(
                using={
                    "field_survey": {
                        "rival_discovery_chance": ParamModifier(op="multiply", value=0.0),
                    },
                },
            ),
            stats_explanation=(
                "Covers one discovered site; multiplies rival_discovery_chance by "
                "0. Successful site disguise XP only when a rival would "
                "have discovered the site without the cover."
            ),
        )
    )
    blackout_cover: DisguiseActionConfig = Field(
        default_factory=lambda: DisguiseActionConfig(
            duration_minutes=60,
            modifies_main_params=ModifiesMainParams(
                using={
                    "field_survey": {
                        "rival_discovery_chance": ParamModifier(op="multiply", value=0.5),
                    },
                },
            ),
            stats_explanation=(
                "Covers one discovered site; multiplies rival_discovery_chance by "
                "0.5. Successful site disguise XP only when a rival would "
                "have discovered the site without the cover but the cover "
                "stops them."
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

    def disguise_config_for(self, action_key: str) -> DisguiseActionConfig:
        mapping = {
            "brush_scrim": self.brush_scrim,
            "blackout_cover": self.blackout_cover,
        }
        try:
            return mapping[action_key]
        except KeyError as exc:
            raise KeyError(f"unknown disguise action: {action_key}") from exc

    def main_param_buff_config_for(self, action_key: str) -> MainParamBuffActionConfig:
        mapping = {
            "ridge_glass": self.ridge_glass,
            "trail_striders": self.trail_striders,
            "expedition_drivetrain": self.expedition_drivetrain,
            "canyon_throttle": self.canyon_throttle,
            "overland_chassis": self.overland_chassis,
            "nocturne_lens": self.nocturne_lens,
        }
        try:
            return mapping[action_key]
        except KeyError as exc:
            raise KeyError(f"unknown main-param buff action: {action_key}") from exc

    def tools_modifying_skill(self, skill_id: str) -> list[tuple[str, ModifiesMainParams]]:
        """Return (action_key, mods) for tools that modify ``skill_id``."""
        out: list[tuple[str, ModifiesMainParams]] = []
        for key, cfg in (
            ("geo_compass", self.geo_compass),
            ("proximity_scanner", self.proximity_scanner),
            ("site_navigator", self.site_navigator),
            ("ridge_glass", self.ridge_glass),
            ("trail_striders", self.trail_striders),
            ("expedition_drivetrain", self.expedition_drivetrain),
            ("canyon_throttle", self.canyon_throttle),
            ("overland_chassis", self.overland_chassis),
            ("nocturne_lens", self.nocturne_lens),
            ("brush_scrim", self.brush_scrim),
            ("blackout_cover", self.blackout_cover),
        ):
            mods = cfg.modifies_main_params
            if mods is not None and mods.affects_skill(skill_id):
                out.append((key, mods))
        return out
