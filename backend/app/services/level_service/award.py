"""Mutate user skill XP / breakdown and sync career xp + level."""

from __future__ import annotations

from typing import Mapping

from app.core.game_config import ParamModifier
from app.models.user import User
from app.services.level_service.main_params import (
    resolve_fossil_detection_main_params,
    resolve_site_discovery_main_params,
    resolve_site_stewardship_main_params,
)
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


def _xp_int(value: float) -> int:
    return max(0, int(round(float(value))))


def award_site_discover_xp(
    user: User,
    *,
    amount: int | None = None,
    weather_time: str | None = None,
    weather_type: str | None = None,
    tool_mods: Mapping[str, ParamModifier] | None = None,
) -> int:
    if amount is None:
        skill_level = level_for_xp(get_skill_xp(user, "site_discovery"))
        resolved = resolve_site_discovery_main_params(
            skill_level=skill_level,
            weather_time=weather_time,
            weather_type=weather_type,
            tool_mods=tool_mods,
        )
        amount = _xp_int(resolved["site_discovery_xp"])
    return award_skill_xp(
        user,
        "site_discovery",
        amount=amount,
        breakdown_delta={"sites": amount},
    )


def award_first_discovery_xp(
    user: User,
    *,
    amount: int | None = None,
    weather_time: str | None = None,
    weather_type: str | None = None,
    tool_mods: Mapping[str, ParamModifier] | None = None,
) -> int:
    """Award site_discovery XP for being the first user to discover a site."""
    if amount is None:
        skill_level = level_for_xp(get_skill_xp(user, "site_discovery"))
        resolved = resolve_site_discovery_main_params(
            skill_level=skill_level,
            weather_time=weather_time,
            weather_type=weather_type,
            tool_mods=tool_mods,
        )
        amount = _xp_int(resolved["first_discovery_xp"])
    if amount <= 0:
        return 0
    return award_skill_xp(
        user,
        "site_discovery",
        amount=amount,
        breakdown_delta={"first_discovery": amount},
    )


def award_fossil_discover_xp(
    user: User,
    *,
    count: int = 1,
    amount_per: int | None = None,
    weather_time: str | None = None,
    weather_type: str | None = None,
    tool_mods: Mapping[str, ParamModifier] | None = None,
) -> int:
    if count <= 0:
        return 0
    if amount_per is None:
        skill_level = level_for_xp(get_skill_xp(user, "fossil_detection"))
        resolved = resolve_fossil_detection_main_params(
            skill_level=skill_level,
            weather_time=weather_time,
            weather_type=weather_type,
            tool_mods=tool_mods,
        )
        amount_per = _xp_int(resolved["fossil_discovery_xp"])
    total = amount_per * int(count)
    return award_skill_xp(
        user,
        "fossil_detection",
        amount=total,
        breakdown_delta={"fossils": total},
    )


def award_successful_site_disguise_xp(
    user: User,
    *,
    amount: int | None = None,
    weather_time: str | None = None,
    weather_type: str | None = None,
    tool_mods: Mapping[str, ParamModifier] | None = None,
) -> int:
    """Award site_stewardship XP when a disguise blocks a would-be rival discovery."""
    if amount is None:
        skill_level = level_for_xp(get_skill_xp(user, "site_stewardship"))
        resolved = resolve_site_stewardship_main_params(
            skill_level=skill_level,
            weather_time=weather_time,
            weather_type=weather_type,
            tool_mods=tool_mods,
        )
        amount = _xp_int(resolved["successful_site_disguise_xp"])
    return award_skill_xp(
        user,
        "site_stewardship",
        amount=amount,
        breakdown_delta={"disguise": amount},
    )


SITE_EXPLORATION_BATCH_M = 20


def exploration_batch_count(meters: float) -> int:
    """Whole 20 m batches completed for the given explored distance."""
    return max(0, int(meters) // SITE_EXPLORATION_BATCH_M)


def award_site_exploration_xp(
    user: User,
    *,
    previous_explored_m: float,
    new_explored_m: float,
    weather_time: str | None = None,
    weather_type: str | None = None,
    tool_mods: Mapping[str, ParamModifier] | None = None,
) -> int:
    """Award site_stewardship XP for whole 20 m exploration floor increases."""
    batch_delta = exploration_batch_count(new_explored_m) - exploration_batch_count(
        previous_explored_m
    )
    if batch_delta <= 0:
        return 0
    skill_level = level_for_xp(get_skill_xp(user, "site_stewardship"))
    resolved = resolve_site_stewardship_main_params(
        skill_level=skill_level,
        weather_time=weather_time,
        weather_type=weather_type,
        tool_mods=tool_mods,
    )
    total = batch_delta * _xp_int(resolved["site_exploration_xp"])
    if total <= 0:
        return 0
    return award_skill_xp(
        user,
        "site_stewardship",
        amount=total,
        breakdown_delta={"site_exploration": total},
    )


def award_site_documentation_xp(
    user: User,
    *,
    amount: int | None = None,
    weather_time: str | None = None,
    weather_type: str | None = None,
    tool_mods: Mapping[str, ParamModifier] | None = None,
) -> int:
    """Award site_stewardship XP when all five dimension accuracies hit 100%."""
    if amount is None:
        skill_level = level_for_xp(get_skill_xp(user, "site_stewardship"))
        resolved = resolve_site_stewardship_main_params(
            skill_level=skill_level,
            weather_time=weather_time,
            weather_type=weather_type,
            tool_mods=tool_mods,
        )
        amount = _xp_int(resolved["site_documentation_xp"])
    if amount <= 0:
        return 0
    return award_skill_xp(
        user,
        "site_stewardship",
        amount=amount,
        breakdown_delta={"site_documentation": amount},
    )


def award_first_documentation_xp(
    user: User,
    *,
    amount: int | None = None,
    weather_time: str | None = None,
    weather_type: str | None = None,
    tool_mods: Mapping[str, ParamModifier] | None = None,
) -> int:
    """Award site_stewardship XP for being the first to fully document a site."""
    if amount is None:
        skill_level = level_for_xp(get_skill_xp(user, "site_stewardship"))
        resolved = resolve_site_stewardship_main_params(
            skill_level=skill_level,
            weather_time=weather_time,
            weather_type=weather_type,
            tool_mods=tool_mods,
        )
        amount = _xp_int(resolved["first_documentation_xp"])
    if amount <= 0:
        return 0
    return award_skill_xp(
        user,
        "site_stewardship",
        amount=amount,
        breakdown_delta={"first_documentation": amount},
    )


# Attempt index (1 = first try, 2 = second, 3 = third) → XP fraction.
_IDENTIFICATION_ATTEMPT_SCALE: dict[int, float] = {
    1: 1.0,
    2: 0.5,
    3: 0.0,
}


def identification_xp_for_attempt(*, base_xp: int, attempt: int) -> int:
    """Scale identification XP by attempt number (1..3)."""
    scale = _IDENTIFICATION_ATTEMPT_SCALE.get(max(1, min(3, int(attempt))), 0.0)
    return int(round(base_xp * scale))


def award_site_identification_xp(
    user: User,
    *,
    attempt: int,
    amount: int | None = None,
    weather_time: str | None = None,
    weather_type: str | None = None,
    tool_mods: Mapping[str, ParamModifier] | None = None,
) -> int:
    """Award site_stewardship XP for a correct identification quiz step."""
    if amount is None:
        skill_level = level_for_xp(get_skill_xp(user, "site_stewardship"))
        resolved = resolve_site_stewardship_main_params(
            skill_level=skill_level,
            weather_time=weather_time,
            weather_type=weather_type,
            tool_mods=tool_mods,
        )
        base = _xp_int(resolved["site_identification_xp"])
        amount = identification_xp_for_attempt(base_xp=base, attempt=attempt)
    if amount <= 0:
        return 0
    return award_skill_xp(
        user,
        "site_stewardship",
        amount=amount,
        breakdown_delta={"site_identification": amount},
    )


def award_distance_xp(
    user: User,
    *,
    active_100m_delta: int,
    passive_km_delta: int,
    weather_time: str | None = None,
    weather_type: str | None = None,
    tool_mods: Mapping[str, ParamModifier] | None = None,
) -> int:
    """Award site-discovery XP for active 100 m / passive km floor increases."""
    skill_level = level_for_xp(get_skill_xp(user, "site_discovery"))
    resolved = resolve_site_discovery_main_params(
        skill_level=skill_level,
        weather_time=weather_time,
        weather_type=weather_type,
        tool_mods=tool_mods,
    )
    active_add = max(0, int(active_100m_delta)) * _xp_int(
        resolved["active_100m_xp"]
    )
    passive_add = max(0, int(passive_km_delta)) * _xp_int(resolved["passive_km_xp"])
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


def whole_100m(meters: float) -> int:
    return max(0, int(meters) // 100)


def whole_km(meters: float) -> int:
    return max(0, int(meters) // 1000)


def passive_meters(total_m: float, active_m: float) -> float:
    return max(0.0, float(total_m) - float(active_m))
