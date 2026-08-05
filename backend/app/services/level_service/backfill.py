"""Retroactive skill XP from discoveries + walked distance."""

from __future__ import annotations

from sqlalchemy import func
from sqlalchemy.orm.attributes import flag_modified
from sqlmodel import Session, col, select

from app.core.game_config import get_game_config
from app.models.user import User
from app.models.user_fossil import USER_FOSSIL_ROLE_IN_SITU, UserFossil
from app.models.user_site import USER_SITE_ROLE_DISCOVERER, UserSite
from app.services.level_service.award import (
    passive_meters,
    sync_career_from_skills,
    whole_100m,
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
            col(UserFossil.role) == USER_FOSSIL_ROLE_IN_SITU,
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
    site_cfg = get_game_config().site_discovery
    fossil_cfg = get_game_config().fossil_detection
    site_xp = int(round(float(site_cfg.discover_site_xp)))
    fossil_xp = int(
        round(float(fossil_cfg.main_params.get("locate_fossil_in_situ_xp", 5)))
    )
    active_xp = int(round(float(site_cfg.explore_100m_actively_xp)))
    passive_xp = int(round(float(site_cfg.explore_1km_passively_xp)))
    from_sites = int(site_count) * site_xp
    from_fossils = int(fossil_count) * fossil_xp
    active_batches = whole_100m(active_distance_m)
    passive_km = whole_km(passive_meters(total_distance_m, active_distance_m))
    from_active = active_batches * active_xp
    from_passive = passive_km * passive_xp

    skill_xp = empty_skill_xp()
    skill_xp["field_survey"] = from_sites + from_active + from_passive
    skill_xp["bone_quarry"] = from_fossils

    breakdown: dict[str, dict[str, int]] = {}
    site_breakdown: dict[str, int] = {}
    if from_sites:
        site_breakdown["discover_site"] = from_sites
    if from_active:
        site_breakdown["explore_100m_actively"] = from_active
    if from_passive:
        site_breakdown["explore_1km_passively"] = from_passive
    if site_breakdown:
        breakdown["field_survey"] = site_breakdown
    if from_fossils:
        breakdown["bone_quarry"] = {"locate_fossil_in_situ": from_fossils}

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
