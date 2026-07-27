"""RuneScape-style XP thresholds (skills) and career thresholds (× skill count)."""

from __future__ import annotations

import math
from bisect import bisect_right
from functools import lru_cache


def xp_for_level(level: int) -> int:
    """Minimum XP required to reach ``level`` (level 1 = 0).

    Classic formula::

        floor(sum(floor(n + 300 * 2^(n/7)) for n in 1..level-1) / 4)
    """
    if level <= 1:
        return 0
    if level > 99:
        level = 99
    total = 0
    for n in range(1, level):
        total += math.floor(n + 300 * (2 ** (n / 7.0)))
    return total // 4


def _build_skill_thresholds() -> tuple[int, ...]:
    """Index 0 unused; index ``L`` = XP required for skill level ``L`` (1..99)."""
    values = [0] * 100
    for level in range(1, 100):
        values[level] = xp_for_level(level)
    return tuple(values)


SKILL_THRESHOLDS: tuple[int, ...] = _build_skill_thresholds()


def career_thresholds(skill_count: int) -> tuple[int, ...]:
    """Career XP thresholds = per-skill thresholds × ``skill_count``."""
    count = max(1, int(skill_count))
    return tuple(t * count for t in SKILL_THRESHOLDS)


@lru_cache(maxsize=8)
def _career_xp_list(skill_count: int) -> list[int]:
    return list(career_thresholds(skill_count)[1:])


def _configured_skill_count() -> int:
    from app.services.level_service.skills import skill_count as configured_skill_count

    return configured_skill_count()


def get_career_thresholds() -> tuple[int, ...]:
    return career_thresholds(_configured_skill_count())


def level_for_xp(xp: int, *, career: bool = False) -> int:
    """Return level in 1..99 for the given XP total."""
    if xp < 0:
        xp = 0
    if career:
        table = _career_xp_list(_configured_skill_count())
    else:
        table = list(SKILL_THRESHOLDS[1:])
    idx = bisect_right(table, xp)
    return max(1, min(99, idx))


def next_level_xp(xp: int, *, career: bool = False) -> int:
    """XP threshold for the next level (current threshold if already 99)."""
    level = level_for_xp(xp, career=career)
    thresholds = get_career_thresholds() if career else SKILL_THRESHOLDS
    if level >= 99:
        return thresholds[99]
    return thresholds[level + 1]


def xp_to_next_level(xp: int, *, career: bool = False) -> int:
    """XP still needed to reach the next level (0 at 99)."""
    return max(0, next_level_xp(xp, career=career) - max(0, int(xp)))


def progress_in_level(xp: int, *, career: bool = False) -> float:
    """Fraction 0..1 of progress from current level toward the next (1.0 at 99)."""
    level = level_for_xp(xp, career=career)
    if level >= 99:
        return 1.0
    thresholds = get_career_thresholds() if career else SKILL_THRESHOLDS
    lo = thresholds[level]
    hi = thresholds[level + 1]
    if hi <= lo:
        return 1.0
    return max(0.0, min(1.0, (xp - lo) / (hi - lo)))


@lru_cache(maxsize=1)
def skill_xp_for_level_99() -> int:
    return SKILL_THRESHOLDS[99]
