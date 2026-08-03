"""Accuracy-aware blurry bands for site odd_* axes (card display)."""

from __future__ import annotations

import hashlib
import random
from dataclasses import dataclass
from enum import IntEnum

from app.core.game_config import get_game_config
from app.services.level_service.main_params import resolve_scalar_main_param

# Keep in sync with Flutter site_dimension_display.dart
_MAX_RANGE_WIDTH = 1.0
_MAX_CENTER_JITTER = 0.45
_MAX_BLUR_SIGMA = 16.0
_DEPTH_PRECISE_EPSILON = 1e-9


class SiteDimensionKey(IntEnum):
    DINO = 0
    FOSSIL = 1
    COMPLETENESS = 2
    QUALITY = 3
    DEPTH = 4


@dataclass(frozen=True)
class SiteDimensionBand:
    range_start: float
    range_end: float
    blur_sigma: float
    effective_accuracy: float


_ACCURACY_KEYS: dict[SiteDimensionKey, str] = {
    SiteDimensionKey.DINO: "dino_accuracy",
    SiteDimensionKey.FOSSIL: "fossil_accuracy",
    SiteDimensionKey.COMPLETENESS: "completeness_accuracy",
    SiteDimensionKey.QUALITY: "quality_accuracy",
    SiteDimensionKey.DEPTH: "depth_accuracy",
}


def resolve_site_survey_accuracies(*, skill_level: int = 1) -> dict[str, float]:
    """Effective site-survey accuracy params: base → level modifiers."""
    cfg = get_game_config().site_survey
    mp = cfg.main_params
    bases = {
        "dino_accuracy": float(mp.dino_accuracy),
        "fossil_accuracy": float(mp.fossil_accuracy),
        "completeness_accuracy": float(mp.completeness_accuracy),
        "quality_accuracy": float(mp.quality_accuracy),
        "depth_accuracy": float(mp.depth_accuracy),
    }
    return {
        key: resolve_scalar_main_param(
            base=base,
            level_entries=list(cfg.level_modifiers.get(key, [])),
            skill_level=skill_level,
            clamp_unit=True,
        )
        for key, base in bases.items()
    }


def resolve_site_dimension_band(
    *,
    dimension: SiteDimensionKey,
    true_value: float,
    accuracy: float,
    site_id: int,
) -> SiteDimensionBand:
    """Stable, accuracy-aware blurry range for one site dimension axis."""
    clamped_true = min(1.0, max(0.0, float(true_value)))
    is_depth_surface = (
        dimension == SiteDimensionKey.DEPTH
        and clamped_true <= _DEPTH_PRECISE_EPSILON
    )
    effective_accuracy = 1.0 if is_depth_surface else min(1.0, max(0.0, float(accuracy)))
    uncertainty = 1.0 - effective_accuracy

    if uncertainty <= 0:
        return SiteDimensionBand(
            range_start=clamped_true,
            range_end=clamped_true,
            blur_sigma=0.0,
            effective_accuracy=effective_accuracy,
        )

    seed_material = f"{int(site_id)}:{int(dimension)}".encode()
    seed = int(hashlib.md5(seed_material).hexdigest()[:8], 16)
    rng = random.Random(seed)

    center_jitter = (rng.random() * 2.0 - 1.0) * uncertainty * _MAX_CENTER_JITTER
    center = min(1.0, max(0.0, clamped_true + center_jitter))

    total_width = uncertainty * _MAX_RANGE_WIDTH
    left_frac = 0.2 + rng.random() * 0.6  # [0.2, 0.8]
    start = center - total_width * left_frac
    end = center + total_width * (1.0 - left_frac)

    if start < 0:
        end = min(1.0, max(0.0, end - start))
        start = 0.0
    if end > 1:
        start = min(1.0, max(0.0, start - (end - 1.0)))
        end = 1.0

    return SiteDimensionBand(
        range_start=start,
        range_end=end,
        blur_sigma=uncertainty * _MAX_BLUR_SIGMA,
        effective_accuracy=effective_accuracy,
    )


def build_site_dimension_bands(
    *,
    site_id: int,
    odd_dino_count: float | None,
    odd_fossil_count: float | None,
    odd_completeness: float | None,
    odd_quality: float | None,
    odd_depth: float | None,
    skill_level: int = 1,
) -> dict[SiteDimensionKey, SiteDimensionBand | None]:
    accuracies = resolve_site_survey_accuracies(skill_level=skill_level)
    values = {
        SiteDimensionKey.DINO: odd_dino_count,
        SiteDimensionKey.FOSSIL: odd_fossil_count,
        SiteDimensionKey.COMPLETENESS: odd_completeness,
        SiteDimensionKey.QUALITY: odd_quality,
        SiteDimensionKey.DEPTH: odd_depth,
    }
    out: dict[SiteDimensionKey, SiteDimensionBand | None] = {}
    for key, true_value in values.items():
        if true_value is None:
            out[key] = None
            continue
        accuracy_key = _ACCURACY_KEYS[key]
        out[key] = resolve_site_dimension_band(
            dimension=key,
            true_value=float(true_value),
            accuracy=accuracies.get(accuracy_key, 0.0),
            site_id=site_id,
        )
    return out
