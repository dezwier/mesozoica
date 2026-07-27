"""Tests for RuneScape-style skill / career leveling."""

from __future__ import annotations

from datetime import date

from sqlmodel import Session

from app.core.game_config import get_game_config
from app.models.user import User
from app.models.user_fossil import USER_FOSSIL_ROLE_DISCOVERER, UserFossil
from app.models.user_site import USER_SITE_ROLE_DISCOVERER, UserSite
from app.schemas.auth import UpdateDistanceRequest
from app.services.level_service import (
    CAREER_THRESHOLDS,
    SKILL_THRESHOLDS,
    award_distance_km_xp,
    award_fossil_discover_xp,
    award_site_discover_xp,
    backfill_user_levels,
    career_title_for_user_xp,
    level_for_xp,
    progress_in_level,
    xp_for_level,
)
from app.services.level_service.backfill import compute_exploration_from_history
from app.services.user_service import user_to_profile_response
from app.services.walk_distance_service import apply_distance_update


def test_xp_for_level_anchors() -> None:
    assert xp_for_level(1) == 0
    assert xp_for_level(2) == 83
    assert xp_for_level(99) == 13_034_431
    assert SKILL_THRESHOLDS[2] == 83
    assert SKILL_THRESHOLDS[99] == 13_034_431
    assert CAREER_THRESHOLDS[2] == 83 * 3
    assert CAREER_THRESHOLDS[99] == 13_034_431 * 3


def test_level_for_xp_skill_and_career() -> None:
    assert level_for_xp(0) == 1
    assert level_for_xp(82) == 1
    assert level_for_xp(83) == 2
    assert level_for_xp(13_034_431) == 99
    assert level_for_xp(13_034_431 * 3, career=True) == 99
    assert level_for_xp(82 * 3, career=True) == 1
    assert level_for_xp(83 * 3, career=True) == 2


def test_progress_in_level() -> None:
    assert progress_in_level(0) == 0.0
    mid = progress_in_level(41)  # halfway-ish toward 83
    assert 0.4 < mid < 0.6
    assert progress_in_level(13_034_431) == 1.0


def test_leveling_yaml_loaded() -> None:
    get_game_config.cache_clear()
    cfg = get_game_config().leveling
    assert cfg.rewards.site_discover_exploration_xp == 30
    assert cfg.rewards.fossil_discover_exploration_xp == 50
    assert cfg.rewards.active_km_exploration_xp == 30
    assert cfg.rewards.passive_km_exploration_xp == 5
    assert len(cfg.titles.exploration) == 99
    assert len(cfg.titles.excavation) == 99
    assert len(cfg.titles.research) == 99


def test_career_title_combines_skill_levels() -> None:
    title = career_title_for_user_xp(0, 0, 0)
    words = title.split()
    assert len(words) == 3
    cfg = get_game_config().leveling.titles
    assert words[0] == cfg.exploration[0]
    assert words[1] == cfg.excavation[0]
    assert words[2] == cfg.research[0]

    # Level 2 exploration (83 XP), others still level 1
    title2 = career_title_for_user_xp(83, 0, 0)
    assert title2.split()[0] == cfg.exploration[1]


def _make_user(session: Session, **kwargs) -> User:
    defaults = dict(
        username="leveler",
        email="leveler@example.com",
        password=User.hash_password("secret"),
    )
    defaults.update(kwargs)
    user = User(**defaults)
    session.add(user)
    session.commit()
    session.refresh(user)
    return user


def test_award_site_and_fossil_xp(session: Session) -> None:
    user = _make_user(session)
    award_site_discover_xp(user)
    award_fossil_discover_xp(user, count=2)
    session.add(user)
    session.commit()
    session.refresh(user)
    assert user.exploration_xp == 30 + 100
    assert user.xp_from_sites == 30
    assert user.xp_from_fossils == 100
    assert user.xp == user.exploration_xp
    assert user.level == level_for_xp(user.xp, career=True)


def test_award_distance_km_xp(session: Session) -> None:
    user = _make_user(session)
    award_distance_km_xp(user, active_km_delta=2, passive_km_delta=3)
    session.add(user)
    session.commit()
    session.refresh(user)
    assert user.xp_from_active_distance == 60
    assert user.xp_from_passive_distance == 15
    assert user.exploration_xp == 75


def test_distance_update_awards_whole_km(session: Session) -> None:
    user = _make_user(session, username="walker", email="walker@example.com")
    apply_distance_update(
        session,
        user,
        UpdateDistanceRequest(
            total_distance_m=2500,
            weekly_distance_m=2500,
            active_distance_m=1200,
            active_weekly_distance_m=1200,
            week_start=date(2026, 7, 20),
        ),
    )
    session.refresh(user)
    # active floor km=1 → 30; passive = 1300m → 1 km → 5
    assert user.xp_from_active_distance == 30
    assert user.xp_from_passive_distance == 5
    assert user.exploration_xp == 35

    # Second sync: active 2200 → +1 km; total 3500 → passive 1300 still 1 km
    apply_distance_update(
        session,
        user,
        UpdateDistanceRequest(
            total_distance_m=3500,
            weekly_distance_m=3500,
            active_distance_m=2200,
            active_weekly_distance_m=2200,
            week_start=date(2026, 7, 20),
        ),
    )
    session.refresh(user)
    assert user.xp_from_active_distance == 60
    assert user.xp_from_passive_distance == 5
    assert user.exploration_xp == 65


def test_backfill_from_history(session: Session) -> None:
    user = _make_user(session, username="backfill", email="backfill@example.com")
    user.total_distance_m = 5000
    user.active_distance_m = 2000
    session.add(user)
    session.commit()

    # Fake discovery rows (site/fossil FKs may be loose on sqlite tests)
    session.add(
        UserSite(user_id=user.id, site_id=1, role=USER_SITE_ROLE_DISCOVERER)
    )
    session.add(
        UserSite(user_id=user.id, site_id=2, role=USER_SITE_ROLE_DISCOVERER)
    )
    session.add(
        UserFossil(
            user_id=user.id, fossil_id=10, role=USER_FOSSIL_ROLE_DISCOVERER
        )
    )
    session.commit()

    expected, *_ = compute_exploration_from_history(
        site_count=2,
        fossil_count=1,
        total_distance_m=5000,
        active_distance_m=2000,
    )
    backfill_user_levels(session, user)
    session.commit()
    session.refresh(user)
    assert user.exploration_xp == expected
    assert user.xp_from_sites == 60
    assert user.xp_from_fossils == 50
    assert user.xp_from_active_distance == 60  # 2 km
    assert user.xp_from_passive_distance == 15  # 3 km
    assert user.excavation_xp == 0
    assert user.research_xp == 0


def test_profile_response_includes_skill_fields(session: Session) -> None:
    user = _make_user(session, username="prof", email="prof@example.com")
    award_site_discover_xp(user)
    session.add(user)
    session.commit()
    session.refresh(user)
    profile = user_to_profile_response(session, user)
    assert profile.exploration_xp == 30
    assert profile.exploration_level == 1
    assert profile.career_title
    assert profile.xp_from_sites == 30
    assert 0.0 <= profile.career_progress <= 1.0
