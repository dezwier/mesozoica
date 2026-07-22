"""Unit tests for odd-score sampling helpers."""

from __future__ import annotations

import random
from collections import Counter

from app.core.game_config import DinoCountThreshold, get_game_config
from app.services.site_service.field_fossil_generate import (
    _sample_distinct_subcategories,
    clamp_odd,
    dino_count_from_score,
    tier_from_cdf,
)

def test_clamp_odd_clamps_and_defaults_missing() -> None:
    rng = random.Random(0)
    assert clamp_odd(None, 0.0, rng=rng) == 0.5
    assert clamp_odd(0.0, 0.0, rng=random.Random(1)) == 0.0
    assert clamp_odd(1.0, 0.0, rng=random.Random(1)) == 1.0
    # Extreme noise always stays in [0, 1].
    for seed in range(20):
        low = clamp_odd(0.0, 5.0, rng=random.Random(seed))
        high = clamp_odd(1.0, 5.0, rng=random.Random(seed))
        assert 0.0 <= low <= 1.0
        assert 0.0 <= high <= 1.0


def test_dino_count_from_score_thresholds() -> None:
    get_game_config.cache_clear()
    thresholds = get_game_config().fossil_generation.dino_count_thresholds
    assert dino_count_from_score(0.0, thresholds) == 0
    assert dino_count_from_score(0.09, thresholds) == 0
    assert dino_count_from_score(0.1, thresholds) == 1
    assert dino_count_from_score(0.59, thresholds) == 1
    assert dino_count_from_score(0.6, thresholds) == 2
    assert dino_count_from_score(0.61, thresholds) == 2
    assert dino_count_from_score(0.95, thresholds) == 5
    assert dino_count_from_score(0.96, thresholds) == 5
    assert dino_count_from_score(1.0, thresholds) == 5


def test_tier_from_cdf_inverse() -> None:
    items = ["a", "b", "c"]
    weights = [0.5, 0.3, 0.2]
    assert tier_from_cdf(0.0, items, weights) == "a"
    assert tier_from_cdf(0.5, items, weights) == "a"
    assert tier_from_cdf(0.51, items, weights) == "b"
    assert tier_from_cdf(0.8, items, weights) == "b"
    assert tier_from_cdf(0.81, items, weights) == "c"
    assert tier_from_cdf(1.0, items, weights) == "c"


def test_dino_count_custom_thresholds() -> None:
    thresholds = [
        DinoCountThreshold(max_odd=0.5, count=1),
        DinoCountThreshold(max_odd=1.0, count=2),
    ]
    assert dino_count_from_score(0.4, thresholds) == 1
    assert dino_count_from_score(0.9, thresholds) == 2


def test_sample_distinct_subcategories_no_repeats() -> None:
    counts = Counter({"teeth": 10, "skull": 5, "vertebrae": 1})
    picked = _sample_distinct_subcategories(
        counts, count=3, default="teeth", rng=random.Random(7)
    )
    assert len(picked) == 3
    assert len(set(picked)) == 3
    assert set(picked) <= {"teeth", "skull", "vertebrae"}


def test_sample_distinct_subcategories_tops_up_when_pool_small() -> None:
    counts = Counter({"teeth": 3})
    picked = _sample_distinct_subcategories(
        counts, count=3, default="teeth", rng=random.Random(3)
    )
    assert len(picked) == 3
    assert len(set(picked)) == 3
    assert "teeth" in picked
