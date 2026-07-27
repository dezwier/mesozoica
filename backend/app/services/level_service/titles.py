"""Resolve career title wording from skill levels + game config."""

from __future__ import annotations

from app.core.game_config import LevelingTitlesConfig, get_game_config
from app.services.level_service.xp_table import level_for_xp


def _word_for_level(words: tuple[str, ...], level: int) -> str:
    if not words:
        return "Unknown"
    idx = max(1, min(99, level)) - 1
    if idx >= len(words):
        idx = len(words) - 1
    return words[idx]


def career_title_for_levels(
    exploration_level: int,
    excavation_level: int,
    research_level: int,
    *,
    titles: LevelingTitlesConfig | None = None,
) -> str:
    cfg = titles if titles is not None else get_game_config().leveling.titles
    return " ".join(
        (
            _word_for_level(cfg.exploration, exploration_level),
            _word_for_level(cfg.excavation, excavation_level),
            _word_for_level(cfg.research, research_level),
        )
    )


def career_title_for_user_xp(
    exploration_xp: int,
    excavation_xp: int,
    research_xp: int,
    *,
    titles: LevelingTitlesConfig | None = None,
) -> str:
    return career_title_for_levels(
        level_for_xp(exploration_xp),
        level_for_xp(excavation_xp),
        level_for_xp(research_xp),
        titles=titles,
    )
