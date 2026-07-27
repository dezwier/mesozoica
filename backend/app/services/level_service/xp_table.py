"""RuneScape-style XP thresholds: skills 1–99, career 1–120 (same formula)."""

from __future__ import annotations

import math
from bisect import bisect_right
from functools import lru_cache

SKILL_MAX_LEVEL = 99
CAREER_MAX_LEVEL = 120


def xp_for_level(level: int) -> int:
    """Minimum XP required to reach ``level`` (level 1 = 0).

    Classic formula::

        floor(sum(floor(n + 300 * 2^(n/7)) for n in 1..level-1) / 4)
    """
    if level <= 1:
        return 0
    total = 0
    for n in range(1, level):
        total += math.floor(n + 300 * (2 ** (n / 7.0)))
    return total // 4


def _build_thresholds(max_level: int) -> tuple[int, ...]:
    """Index 0 unused; index ``L`` = XP required for level ``L`` (1..max_level)."""
    values = [0] * (max_level + 1)
    for level in range(1, max_level + 1):
        values[level] = xp_for_level(level)
    return tuple(values)


SKILL_THRESHOLDS: tuple[int, ...] = _build_thresholds(SKILL_MAX_LEVEL)
CAREER_THRESHOLDS: tuple[int, ...] = _build_thresholds(CAREER_MAX_LEVEL)

_SKILL_XP_LIST: list[int] = list(SKILL_THRESHOLDS[1:])
_CAREER_XP_LIST: list[int] = list(CAREER_THRESHOLDS[1:])


def get_career_thresholds() -> tuple[int, ...]:
    return CAREER_THRESHOLDS


def level_for_xp(xp: int, *, career: bool = False) -> int:
    """Return level for the given XP total (skills 1..99, career 1..120)."""
    if xp < 0:
        xp = 0
    if career:
        table = _CAREER_XP_LIST
        max_level = CAREER_MAX_LEVEL
    else:
        table = _SKILL_XP_LIST
        max_level = SKILL_MAX_LEVEL
    idx = bisect_right(table, xp)
    return max(1, min(max_level, idx))


def next_level_xp(xp: int, *, career: bool = False) -> int:
    """XP threshold for the next level (cap threshold if already max)."""
    level = level_for_xp(xp, career=career)
    max_level = CAREER_MAX_LEVEL if career else SKILL_MAX_LEVEL
    thresholds = CAREER_THRESHOLDS if career else SKILL_THRESHOLDS
    if level >= max_level:
        return thresholds[max_level]
    return thresholds[level + 1]


def xp_to_next_level(xp: int, *, career: bool = False) -> int:
    """XP still needed to reach the next level (0 at max)."""
    return max(0, next_level_xp(xp, career=career) - max(0, int(xp)))


def progress_in_level(xp: int, *, career: bool = False) -> float:
    """Fraction 0..1 of progress from current level toward the next (1.0 at max)."""
    level = level_for_xp(xp, career=career)
    max_level = CAREER_MAX_LEVEL if career else SKILL_MAX_LEVEL
    if level >= max_level:
        return 1.0
    thresholds = CAREER_THRESHOLDS if career else SKILL_THRESHOLDS
    lo = thresholds[level]
    hi = thresholds[level + 1]
    if hi <= lo:
        return 1.0
    return max(0.0, min(1.0, (xp - lo) / (hi - lo)))


@lru_cache(maxsize=1)
def skill_xp_for_level_99() -> int:
    return SKILL_THRESHOLDS[SKILL_MAX_LEVEL]
