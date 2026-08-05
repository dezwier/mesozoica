"""Mutate user skill XP / breakdown and sync career xp + level."""

from __future__ import annotations

from typing import Mapping

from app.core.game_config import ParamModifier
from app.models.user import User
from app.services.level_service.main_params import (
    resolve_bone_quarry_main_params,
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
        skill_level = level_for_xp(get_skill_xp(user, "field_survey"))
        resolved = resolve_site_discovery_main_params(
            skill_level=skill_level,
            weather_time=weather_time,
            weather_type=weather_type,
            tool_mods=tool_mods,
        )
        amount = _xp_int(resolved["discover_site_xp"])
    return award_skill_xp(
        user,
        "field_survey",
        amount=amount,
        breakdown_delta={"discover_site": amount},
    )


def award_discover_site_as_first_xp(
    user: User,
    *,
    amount: int | None = None,
    weather_time: str | None = None,
    weather_type: str | None = None,
    tool_mods: Mapping[str, ParamModifier] | None = None,
) -> int:
    """Award site_discovery XP for being the first user to discover a site."""
    if amount is None:
        skill_level = level_for_xp(get_skill_xp(user, "field_survey"))
        resolved = resolve_site_discovery_main_params(
            skill_level=skill_level,
            weather_time=weather_time,
            weather_type=weather_type,
            tool_mods=tool_mods,
        )
        amount = _xp_int(resolved["discover_site_as_first_xp"])
    if amount <= 0:
        return 0
    return award_skill_xp(
        user,
        "field_survey",
        amount=amount,
        breakdown_delta={"discover_site_as_first": amount},
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
        skill_level = level_for_xp(get_skill_xp(user, "bone_quarry"))
        resolved = resolve_bone_quarry_main_params(
            skill_level=skill_level,
            weather_time=weather_time,
            weather_type=weather_type,
            tool_mods=tool_mods,
        )
        amount_per = _xp_int(resolved["locate_fossil_in_situ_xp"])
    total = amount_per * int(count)
    return award_skill_xp(
        user,
        "bone_quarry",
        amount=total,
        breakdown_delta={"locate_fossil_in_situ": total},
    )


def award_disguise_of_site_xp(
    user: User,
    *,
    amount: int | None = None,
    weather_time: str | None = None,
    weather_type: str | None = None,
    tool_mods: Mapping[str, ParamModifier] | None = None,
) -> int:
    """Award site_stewardship XP when a disguise blocks a would-be rival discovery."""
    if amount is None:
        skill_level = level_for_xp(get_skill_xp(user, "field_survey"))
        resolved = resolve_site_stewardship_main_params(
            skill_level=skill_level,
            weather_time=weather_time,
            weather_type=weather_type,
            tool_mods=tool_mods,
        )
        amount = _xp_int(resolved["disguise_of_site_xp"])
    return award_skill_xp(
        user,
        "field_survey",
        amount=amount,
        breakdown_delta={"disguise_of_site": amount},
    )


SITE_EXPLORATION_BATCH_M = 20


def exploration_batch_count(meters: float) -> int:
    """Whole 20 m batches completed for the given explored distance."""
    return max(0, int(meters) // SITE_EXPLORATION_BATCH_M)


def award_document_progress_xp(
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
    skill_level = level_for_xp(get_skill_xp(user, "field_survey"))
    resolved = resolve_site_stewardship_main_params(
        skill_level=skill_level,
        weather_time=weather_time,
        weather_type=weather_type,
        tool_mods=tool_mods,
    )
    total = batch_delta * _xp_int(resolved["document_progress_xp"])
    if total <= 0:
        return 0
    return award_skill_xp(
        user,
        "field_survey",
        amount=total,
        breakdown_delta={"document_progress": total},
    )


def award_document_site_xp(
    user: User,
    *,
    amount: int | None = None,
    weather_time: str | None = None,
    weather_type: str | None = None,
    tool_mods: Mapping[str, ParamModifier] | None = None,
) -> int:
    """Award site_stewardship XP when all five dimension accuracies hit 100%."""
    if amount is None:
        skill_level = level_for_xp(get_skill_xp(user, "field_survey"))
        resolved = resolve_site_stewardship_main_params(
            skill_level=skill_level,
            weather_time=weather_time,
            weather_type=weather_type,
            tool_mods=tool_mods,
        )
        amount = _xp_int(resolved["document_site_xp"])
    if amount <= 0:
        return 0
    return award_skill_xp(
        user,
        "field_survey",
        amount=amount,
        breakdown_delta={"document_site": amount},
    )


def award_document_site_as_first_xp(
    user: User,
    *,
    amount: int | None = None,
    weather_time: str | None = None,
    weather_type: str | None = None,
    tool_mods: Mapping[str, ParamModifier] | None = None,
) -> int:
    """Award site_stewardship XP for being the first to fully document a site."""
    if amount is None:
        skill_level = level_for_xp(get_skill_xp(user, "field_survey"))
        resolved = resolve_site_stewardship_main_params(
            skill_level=skill_level,
            weather_time=weather_time,
            weather_type=weather_type,
            tool_mods=tool_mods,
        )
        amount = _xp_int(resolved["document_site_as_first_xp"])
    if amount <= 0:
        return 0
    return award_skill_xp(
        user,
        "field_survey",
        amount=amount,
        breakdown_delta={"document_site_as_first": amount},
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


def award_identify_site_xp(
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
        skill_level = level_for_xp(get_skill_xp(user, "field_survey"))
        resolved = resolve_site_stewardship_main_params(
            skill_level=skill_level,
            weather_time=weather_time,
            weather_type=weather_type,
            tool_mods=tool_mods,
        )
        base = _xp_int(resolved["identify_site_xp"])
        amount = identification_xp_for_attempt(base_xp=base, attempt=attempt)
    if amount <= 0:
        return 0
    return award_skill_xp(
        user,
        "field_survey",
        amount=amount,
        breakdown_delta={"identify_site": amount},
    )


def award_distance_xp(
    user: User,
    *,
    active_100m_delta: int,
    passive_10m_delta: int,
    weather_time: str | None = None,
    weather_type: str | None = None,
    tool_mods: Mapping[str, ParamModifier] | None = None,
) -> int:
    """Award site-discovery XP for active 100 m / passive 10 m floor increases.

    Passive rate is [explore_100m_passively_xp] per 100 m → XP/10 m = rate / 10
    (e.g. 10 XP/100 m → 1 XP per 10 m). Gaps under 10 m grant nothing.
    """
    skill_level = level_for_xp(get_skill_xp(user, "field_survey"))
    resolved = resolve_site_discovery_main_params(
        skill_level=skill_level,
        weather_time=weather_time,
        weather_type=weather_type,
        tool_mods=tool_mods,
    )
    active_add = max(0, int(active_100m_delta)) * _xp_int(
        resolved["explore_100m_actively_xp"]
    )
    # Pro-rata: explore_100m_passively_xp is XP per 100 m → per 10 m unit.
    xp_per_10m = float(resolved["explore_100m_passively_xp"]) / 10.0
    passive_add = int(round(max(0, int(passive_10m_delta)) * xp_per_10m))
    total = active_add + passive_add
    if total <= 0:
        return 0
    breakdown: dict[str, int] = {}
    if active_add:
        breakdown["explore_100m_actively"] = active_add
    if passive_add:
        breakdown["explore_100m_passively"] = passive_add
    return award_skill_xp(
        user,
        "field_survey",
        amount=total,
        breakdown_delta=breakdown,
    )


def whole_100m(meters: float) -> int:
    return max(0, int(meters) // 100)


def whole_10m(meters: float) -> int:
    """Whole 10 m batches (passive XP unit; &lt; 10 m → 0)."""
    return max(0, int(meters) // 10)


def whole_km(meters: float) -> int:
    return max(0, int(meters) // 1000)


def passive_meters(total_m: float, active_m: float) -> float:
    return max(0.0, float(total_m) - float(active_m))
