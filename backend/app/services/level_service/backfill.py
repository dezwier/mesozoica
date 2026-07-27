"""Retroactive skill XP from discoveries + walked distance."""

from __future__ import annotations

from sqlalchemy import func
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


def compute_exploration_from_history(
    *,
    site_count: int,
    fossil_count: int,
    total_distance_m: float,
    active_distance_m: float,
) -> tuple[int, int, int, int, int]:
    """Return (exploration_xp, from_sites, from_fossils, from_active, from_passive)."""
    rewards = get_game_config().leveling.rewards
    from_sites = int(site_count) * int(rewards.site_discover_exploration_xp)
    from_fossils = int(fossil_count) * int(rewards.fossil_discover_exploration_xp)
    active_km = whole_km(active_distance_m)
    passive_km = whole_km(passive_meters(total_distance_m, active_distance_m))
    from_active = active_km * int(rewards.active_km_exploration_xp)
    from_passive = passive_km * int(rewards.passive_km_exploration_xp)
    total = from_sites + from_fossils + from_active + from_passive
    return total, from_sites, from_fossils, from_active, from_passive


def backfill_user_levels(session: Session, user: User) -> User:
    """Overwrite skill XP from historical discoveries + distance; sync career."""
    uid = int(user.id)
    sites = _discoverer_site_count(session, uid)
    fossils = _discoverer_fossil_count(session, uid)
    total, from_sites, from_fossils, from_active, from_passive = (
        compute_exploration_from_history(
            site_count=sites,
            fossil_count=fossils,
            total_distance_m=float(user.total_distance_m or 0.0),
            active_distance_m=float(user.active_distance_m or 0.0),
        )
    )
    user.exploration_xp = total
    user.excavation_xp = 0
    user.research_xp = 0
    user.xp_from_sites = from_sites
    user.xp_from_fossils = from_fossils
    user.xp_from_active_distance = from_active
    user.xp_from_passive_distance = from_passive
    sync_career_from_skills(user)
    session.add(user)
    return user


def backfill_all_users(session: Session) -> int:
    """Backfill every user. Returns count processed."""
    users = session.exec(select(User)).all()
    for user in users:
        backfill_user_levels(session, user)
    session.commit()
    return len(users)
