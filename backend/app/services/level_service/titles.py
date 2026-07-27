"""Resolve career title from career level + game config."""

from __future__ import annotations

from app.core.game_config import get_game_config
from app.services.level_service.xp_table import level_for_xp


def _title_for_level(level: int) -> str:
    titles = get_game_config().leveling.career_titles
    if not titles:
        return "Unknown"
    # Titles cover levels 1..len(titles); higher career levels reuse the top title.
    idx = max(1, int(level)) - 1
    if idx >= len(titles):
        idx = len(titles) - 1
    return titles[idx]


def career_title_for_level(level: int) -> str:
    return _title_for_level(level)


def career_title_for_user_xp(career_xp: int) -> str:
    return career_title_for_level(level_for_xp(career_xp, career=True))
