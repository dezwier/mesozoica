"""Retroactive skill XP from discoveries + walked distance."""

from __future__ import annotations

from sqlalchemy import func
from sqlalchemy.orm.attributes import flag_modified
from sqlmodel import Session, col, select

from app.core.game_config import get_game_config
from app.models.user import User
from app.models.user_fossil import USER_FOSSIL_ROLE_DISCOVERER, UserFossil
from app.models.user_site import USER_SITE_ROLE_DISCOVERER, UserSite
from app.services.level_service.award import (
    passive_meters,
    sync_career_from_skills,
    whole_km,
)
from app.services.level_service.skills import empty_skill_xp, skill_ids


def _discoverer_site_count(session: Session, user_id: int) -> int:
    count = session.exec(
        select(func.count()).select_from(UserSite).where(
            col(UserSite.user_id) == user_id,
            col(UserSite.role) == USER_SITE_ROLE_DISCOVERER,
        )
    ).one()
    return int(count or 0)


def _discoverer_fossil_count(session: Session, user_id: int) -> int:
    count = session.exec(
        select(func.count()).select_from(UserFossil).where(
            col(UserFossil.user_id) == user_id,
            col(UserFossil.role) == USER_FOSSIL_ROLE_DISCOVERER,
        )
    ).one()
    return int(count or 0)


def compute_skill_xp_from_history(
    *,
    site_count: int,
    fossil_count: int,
    total_distance_m: float,
    active_distance_m: float,
) -> tuple[dict[str, int], dict[str, dict[str, int]]]:
    """Return (skill_xp, skill_breakdown) from historical activity."""
    rewards = get_game_config().leveling.rewards
    from_sites = int(site_count) * int(rewards.site_discover_site_discovery_xp)
    from_fossils = int(fossil_count) * int(
        rewards.fossil_discover_fossil_detection_xp
    )
    active_km = whole_km(active_distance_m)
    passive_km = whole_km(passive_meters(total_distance_m, active_distance_m))
    from_active = active_km * int(rewards.active_km_site_discovery_xp)
    from_passive = passive_km * int(rewards.passive_km_site_discovery_xp)

    skill_xp = empty_skill_xp()
    skill_xp["site_discovery"] = from_sites + from_active + from_passive
    skill_xp["fossil_detection"] = from_fossils

    breakdown: dict[str, dict[str, int]] = {}
    site_breakdown: dict[str, int] = {}
    if from_sites:
        site_breakdown["sites"] = from_sites
    if from_active:
        site_breakdown["active_distance"] = from_active
    if from_passive:
        site_breakdown["passive_distance"] = from_passive
    if site_breakdown:
        breakdown["site_discovery"] = site_breakdown
    if from_fossils:
        breakdown["fossil_detection"] = {"fossils": from_fossils}

    return skill_xp, breakdown


def backfill_user_levels(session: Session, user: User) -> User:
    """Overwrite skill XP from historical discoveries + distance; sync career."""
    uid = int(user.id)
    sites = _discoverer_site_count(session, uid)
    fossils = _discoverer_fossil_count(session, uid)
    skill_xp, breakdown = compute_skill_xp_from_history(
        site_count=sites,
        fossil_count=fossils,
        total_distance_m=float(user.total_distance_m or 0.0),
        active_distance_m=float(user.active_distance_m or 0.0),
    )
    # Ensure every configured skill key exists.
    for skill_id in skill_ids():
        skill_xp.setdefault(skill_id, 0)
    user.skill_xp = dict(skill_xp)
    user.skill_breakdown = dict(breakdown)
    flag_modified(user, "skill_xp")
    flag_modified(user, "skill_breakdown")
    sync_career_from_skills(user)
    session.add(user)
    return user


def backfill_all_users(session: Session, *, commit: bool = True) -> int:
    """Backfill every user. Returns count processed."""
    users = session.exec(select(User)).all()
    for user in users:
        backfill_user_levels(session, user)
    if commit:
        session.commit()
    else:
        session.flush()
    return len(users)
