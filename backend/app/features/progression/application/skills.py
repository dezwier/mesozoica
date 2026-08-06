"""Skill registry and per-user skill XP helpers."""

from __future__ import annotations

from typing import Any

from sqlalchemy.orm.attributes import flag_modified

from app.core.game_config import LevelingSkillConfig, get_game_config
from app.models.user import User
from app.features.progression.application.xp_table import (
    level_for_xp,
    next_level_xp,
    progress_in_level,
    xp_to_next_level,
)


def skill_ids() -> tuple[str, ...]:
    return tuple(skill.id for skill in get_game_config().leveling.skills)


def skill_count() -> int:
    return len(get_game_config().leveling.skills)


def skill_by_id(skill_id: str) -> LevelingSkillConfig | None:
    for skill in get_game_config().leveling.skills:
        if skill.id == skill_id:
            return skill
    return None


def _ensure_skill_maps(user: User) -> tuple[dict[str, int], dict[str, dict[str, int]]]:
    if user.skill_xp is None:
        user.skill_xp = {}
    if user.skill_breakdown is None:
        user.skill_breakdown = {}
    return user.skill_xp, user.skill_breakdown


def empty_skill_xp() -> dict[str, int]:
    return {skill_id: 0 for skill_id in skill_ids()}


def get_skill_xp(user: User, skill_id: str) -> int:
    skill_xp, _ = _ensure_skill_maps(user)
    return int(skill_xp.get(skill_id, 0))


def set_skill_xp(user: User, skill_id: str, amount: int) -> None:
    skill_xp, _ = _ensure_skill_maps(user)
    skill_xp = dict(skill_xp)
    skill_xp[skill_id] = max(0, int(amount))
    user.skill_xp = skill_xp
    flag_modified(user, "skill_xp")


def add_skill_breakdown(
    user: User,
    skill_id: str,
    *,
    deltas: dict[str, int],
) -> None:
    _, breakdown = _ensure_skill_maps(user)
    bucket = dict(breakdown.get(skill_id, {}))
    for key, delta in deltas.items():
        if delta:
            bucket[key] = int(bucket.get(key, 0)) + int(delta)
    breakdown = dict(breakdown)
    if bucket:
        breakdown[skill_id] = bucket
    user.skill_breakdown = breakdown
    flag_modified(user, "skill_breakdown")


def total_skill_xp(user: User) -> int:
    skill_xp, _ = _ensure_skill_maps(user)
    return sum(int(skill_xp.get(skill_id, 0)) for skill_id in skill_ids())


def skill_state(user: User, skill_id: str) -> dict[str, Any]:
    skill = skill_by_id(skill_id)
    if skill is None:
        raise ValueError(f"unknown skill id: {skill_id}")
    xp = get_skill_xp(user, skill_id)
    level = level_for_xp(xp)
    return {
        "id": skill.id,
        "name": skill.name,
        "xp": xp,
        "level": level,
        "next_level_xp": next_level_xp(xp),
        "xp_to_next": xp_to_next_level(xp),
        "progress": progress_in_level(xp),
    }


def all_skill_states(user: User) -> list[dict[str, Any]]:
    return [skill_state(user, skill.id) for skill in get_game_config().leveling.skills]


def career_state(user: User) -> dict[str, Any]:
    from app.features.progression.application.titles import career_title_for_level

    xp = total_skill_xp(user)
    level = level_for_xp(xp, career=True)
    return {
        "xp": xp,
        "level": level,
        "title": career_title_for_level(level),
        "next_level_xp": next_level_xp(xp, career=True),
        "xp_to_next": xp_to_next_level(xp, career=True),
        "progress": progress_in_level(xp, career=True),
    }
