"""Mutate user skill XP / breakdown and sync career xp + level."""

from __future__ import annotations

from app.core.game_config import get_game_config
from app.models.user import User
from app.services.level_service.skills import (
    add_skill_breakdown,
    get_skill_xp,
    set_skill_xp,
    total_skill_xp,
)
from app.services.level_service.xp_table import level_for_xp


def sync_career_from_skills(user: User) -> None:
    """Set ``user.xp`` / ``user.level`` from the sum of all skill XP."""
    career_xp = total_skill_xp(user)
    user.xp = career_xp
    user.level = level_for_xp(career_xp, career=True)


def award_skill_xp(
    user: User,
    skill_id: str,
    *,
    amount: int,
    breakdown_delta: dict[str, int] | None = None,
) -> int:
    """Add XP to a skill and optional breakdown deltas. Returns amount added."""
    add = max(0, int(amount))
    if add <= 0 and not breakdown_delta:
        return 0
    if add > 0:
        set_skill_xp(user, skill_id, get_skill_xp(user, skill_id) + add)
    if breakdown_delta:
        add_skill_breakdown(user, skill_id, deltas=breakdown_delta)
    sync_career_from_skills(user)
    return add


def award_site_discover_xp(user: User) -> int:
    amount = int(get_game_config().leveling.rewards.site_discover_site_discovery_xp)
    return award_skill_xp(
        user,
        "site_discovery",
        amount=amount,
        breakdown_delta={"sites": amount},
    )


def award_fossil_discover_xp(user: User, *, count: int = 1) -> int:
    if count <= 0:
        return 0
    per = int(get_game_config().leveling.rewards.fossil_discover_fossil_detection_xp)
    total = per * int(count)
    return award_skill_xp(
        user,
        "fossil_detection",
        amount=total,
        breakdown_delta={"fossils": total},
    )


def award_distance_km_xp(
    user: User,
    *,
    active_km_delta: int,
    passive_km_delta: int,
) -> int:
    """Award site-discovery XP for whole-kilometer floor increases."""
    rewards = get_game_config().leveling.rewards
    active_add = max(0, int(active_km_delta)) * int(rewards.active_km_site_discovery_xp)
    passive_add = max(0, int(passive_km_delta)) * int(
        rewards.passive_km_site_discovery_xp
    )
    total = active_add + passive_add
    if total <= 0:
        return 0
    breakdown: dict[str, int] = {}
    if active_add:
        breakdown["active_distance"] = active_add
    if passive_add:
        breakdown["passive_distance"] = passive_add
    return award_skill_xp(
        user,
        "site_discovery",
        amount=total,
        breakdown_delta=breakdown,
    )


def whole_km(meters: float) -> int:
    return max(0, int(meters) // 1000)


def passive_meters(total_m: float, active_m: float) -> float:
    return max(0.0, float(total_m) - float(active_m))
