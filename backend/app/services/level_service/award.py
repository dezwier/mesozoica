"""Mutate user skill XP / breakdown and sync career xp + level."""

from __future__ import annotations

from app.core.game_config import get_game_config
from app.models.user import User
from app.services.level_service.xp_table import average_skill_level, level_for_xp


def sync_career_from_skills(user: User) -> None:
    """Set ``user.xp`` / ``user.level`` from the three skill totals.

    ``xp`` remains the sum of skill XP. ``level`` is the rounded average of
    the three skill levels.
    """
    exploration_xp = int(user.exploration_xp or 0)
    excavation_xp = int(user.excavation_xp or 0)
    research_xp = int(user.research_xp or 0)
    user.xp = exploration_xp + excavation_xp + research_xp
    user.level = average_skill_level(
        level_for_xp(exploration_xp),
        level_for_xp(excavation_xp),
        level_for_xp(research_xp),
    )


def award_exploration_xp(
    user: User,
    *,
    amount: int,
    from_sites: int = 0,
    from_fossils: int = 0,
    from_active_distance: int = 0,
    from_passive_distance: int = 0,
) -> int:
    """Add exploration XP and optional breakdown deltas. Returns amount added."""
    if amount <= 0 and not any(
        (from_sites, from_fossils, from_active_distance, from_passive_distance)
    ):
        return 0
    add = max(0, int(amount))
    user.exploration_xp = int(user.exploration_xp or 0) + add
    if from_sites:
        user.xp_from_sites = int(user.xp_from_sites or 0) + int(from_sites)
    if from_fossils:
        user.xp_from_fossils = int(user.xp_from_fossils or 0) + int(from_fossils)
    if from_active_distance:
        user.xp_from_active_distance = int(user.xp_from_active_distance or 0) + int(
            from_active_distance
        )
    if from_passive_distance:
        user.xp_from_passive_distance = int(user.xp_from_passive_distance or 0) + int(
            from_passive_distance
        )
    sync_career_from_skills(user)
    return add


def award_site_discover_xp(user: User) -> int:
    amount = int(get_game_config().leveling.rewards.site_discover_exploration_xp)
    return award_exploration_xp(user, amount=amount, from_sites=amount)


def award_fossil_discover_xp(user: User, *, count: int = 1) -> int:
    if count <= 0:
        return 0
    per = int(get_game_config().leveling.rewards.fossil_discover_exploration_xp)
    total = per * int(count)
    return award_exploration_xp(user, amount=total, from_fossils=total)


def award_distance_km_xp(
    user: User,
    *,
    active_km_delta: int,
    passive_km_delta: int,
) -> int:
    """Award exploration XP for whole-kilometer floor increases."""
    rewards = get_game_config().leveling.rewards
    active_add = max(0, int(active_km_delta)) * int(rewards.active_km_exploration_xp)
    passive_add = max(0, int(passive_km_delta)) * int(rewards.passive_km_exploration_xp)
    total = active_add + passive_add
    if total <= 0:
        return 0
    return award_exploration_xp(
        user,
        amount=total,
        from_active_distance=active_add,
        from_passive_distance=passive_add,
    )


def whole_km(meters: float) -> int:
    return max(0, int(meters) // 1000)


def passive_meters(total_m: float, active_m: float) -> float:
    return max(0.0, float(total_m) - float(active_m))
