"""Tests for RuneScape-style skill / career leveling."""

from __future__ import annotations

from datetime import date

from sqlmodel import Session

from app.core.game_config import get_game_config
from app.models.user import User
from app.models.user_fossil import USER_FOSSIL_ROLE_IN_SITU, UserFossil
from app.models.user_site import USER_SITE_ROLE_DISCOVERER, UserSite
from app.schemas.auth import UpdateDistanceRequest
from app.services.level_service import (
    CAREER_THRESHOLDS,
    SKILL_THRESHOLDS,
    award_distance_xp,
    award_discover_site_as_first_xp,
    award_document_site_as_first_xp,
    award_fossil_discover_xp,
    award_site_discover_xp,
    award_document_site_xp,
    backfill_user_levels,
    career_title_for_level,
    career_title_for_user_xp,
    get_career_thresholds,
    get_skill_xp,
    level_for_xp,
    progress_in_level,
    xp_for_level,
)
from app.services.level_service.backfill import compute_skill_xp_from_history
from app.services.user_service import user_to_profile_response
from app.services.walk_distance_service import apply_distance_update


def test_xp_for_level_anchors() -> None:
    assert xp_for_level(1) == 0
    assert xp_for_level(2) == 83
    assert xp_for_level(99) == 13_034_431
    assert SKILL_THRESHOLDS[2] == 83
    assert SKILL_THRESHOLDS[99] == 13_034_431
    assert CAREER_THRESHOLDS[2] == 83
    assert CAREER_THRESHOLDS[99] == 13_034_431
    assert CAREER_THRESHOLDS[120] == xp_for_level(120)
    assert CAREER_THRESHOLDS[120] > CAREER_THRESHOLDS[99]


def test_level_for_xp_skill_and_career() -> None:
    assert level_for_xp(0) == 1
    assert level_for_xp(82) == 1
    assert level_for_xp(83) == 2
    assert level_for_xp(13_034_431) == 99
    assert level_for_xp(83, career=True) == 2
    assert level_for_xp(13_034_431, career=True) == 99
    assert level_for_xp(CAREER_THRESHOLDS[120], career=True) == 120
    assert get_career_thresholds()[2] == 83


def test_progress_in_level() -> None:
    assert progress_in_level(0) == 0.0
    mid = progress_in_level(41)  # halfway-ish toward 83
    assert 0.4 < mid < 0.6
    assert progress_in_level(13_034_431) == 1.0


def test_leveling_yaml_loaded() -> None:
    get_game_config.cache_clear()
    cfg = get_game_config().leveling
    site = get_game_config().site_discovery
    fossil = get_game_config().fossil_detection
    assert site.discover_site_xp == 20
    assert site.discover_site_as_first_xp == 20
    assert site.explore_100m_actively_xp == 20
    assert site.explore_100m_passively_xp == 10
    assert float(fossil.main_params["locate_fossil_in_situ_xp"]) == 20
    assert len(cfg.skills) == 3
    assert cfg.skills[0].id == "field_survey"
    assert cfg.skills[1].id == "bone_quarry"
    assert cfg.skills[2].id == "science_hall"
    assert len(cfg.career_titles) == 99


def test_career_title_from_career_level() -> None:
    cfg = get_game_config().leveling
    assert career_title_for_user_xp(0) == cfg.career_titles[0]
    title2 = career_title_for_user_xp(83)
    assert title2 == cfg.career_titles[1]
    # Levels past the title list reuse the top title.
    assert career_title_for_level(120) == cfg.career_titles[-1]


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
    award_discover_site_as_first_xp(user)
    award_fossil_discover_xp(user, count=2)
    session.add(user)
    session.commit()
    session.refresh(user)
    assert get_skill_xp(user, "field_survey") == 40
    assert get_skill_xp(user, "bone_quarry") == 40
    assert user.skill_breakdown["field_survey"]["discover_site"] == 20
    assert user.skill_breakdown["field_survey"]["discover_site_as_first"] == 20
    assert user.skill_breakdown["bone_quarry"]["locate_fossil_in_situ"] == 40
    assert user.xp == 80
    assert user.level == level_for_xp(user.xp, career=True)


def test_award_document_site_as_first_xp(session: Session) -> None:
    user = _make_user(session, username="doc_first", email="doc_first@example.com")
    award_document_site_xp(user)
    award_document_site_as_first_xp(user)
    session.add(user)
    session.commit()
    session.refresh(user)
    assert get_skill_xp(user, "field_survey") == 100
    assert user.skill_breakdown["field_survey"]["document_site"] == 80
    assert user.skill_breakdown["field_survey"]["document_site_as_first"] == 20


def test_award_distance_xp(session: Session) -> None:
    user = _make_user(session)
    award_distance_xp(user, active_100m_delta=2, passive_10m_delta=300)
    session.add(user)
    session.commit()
    session.refresh(user)
    breakdown = user.skill_breakdown["field_survey"]
    assert breakdown["explore_100m_actively"] == 40
    # 300 × 10 m at 10 XP/100 m → 300 XP
    assert breakdown["explore_100m_passively"] == 300
    assert get_skill_xp(user, "field_survey") == 340


def test_award_distance_xp_pro_rata_10m(session: Session) -> None:
    user = _make_user(session)
    # 10 m → 1 XP; 100 m → 10 XP
    award_distance_xp(user, active_100m_delta=0, passive_10m_delta=1)
    award_distance_xp(user, active_100m_delta=0, passive_10m_delta=10)
    session.add(user)
    session.commit()
    session.refresh(user)
    assert user.skill_breakdown["field_survey"]["explore_100m_passively"] == 11
    assert get_skill_xp(user, "field_survey") == 11


def test_distance_update_awards_active_100m_and_passive_km(session: Session) -> None:
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
    breakdown = user.skill_breakdown["field_survey"]
    # 12 × 100 m active × 20 XP + 1300 m passive × 0.1 XP/m = 130 XP
    assert breakdown["explore_100m_actively"] == 240
    assert breakdown["explore_100m_passively"] == 130
    assert get_skill_xp(user, "field_survey") == 370

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
    breakdown = user.skill_breakdown["field_survey"]
    # +10 active 100 m batches; passive still 1300 m
    assert breakdown["explore_100m_actively"] == 440
    assert breakdown["explore_100m_passively"] == 130
    assert get_skill_xp(user, "field_survey") == 570


def test_backfill_from_history(session: Session) -> None:
    user = _make_user(session, username="backfill", email="backfill@example.com")
    user.total_distance_m = 5000
    user.active_distance_m = 2000
    session.add(user)
    session.commit()

    session.add(
        UserSite(user_id=user.id, site_id=1, role=USER_SITE_ROLE_DISCOVERER)
    )
    session.add(
        UserSite(user_id=user.id, site_id=2, role=USER_SITE_ROLE_DISCOVERER)
    )
    session.add(
        UserFossil(
            user_id=user.id, fossil_id=10, role=USER_FOSSIL_ROLE_IN_SITU
        )
    )
    session.commit()

    skill_xp, breakdown = compute_skill_xp_from_history(
        site_count=2,
        fossil_count=1,
        total_distance_m=5000,
        active_distance_m=2000,
    )
    backfill_user_levels(session, user)
    session.commit()
    session.refresh(user)
    assert user.skill_xp["field_survey"] == skill_xp["field_survey"]
    assert user.skill_xp["bone_quarry"] == skill_xp["bone_quarry"]
    assert user.skill_breakdown["field_survey"]["discover_site"] == 40
    assert user.skill_breakdown["bone_quarry"]["locate_fossil_in_situ"] == 20
    assert user.skill_breakdown["field_survey"]["explore_100m_actively"] == 400
    assert user.skill_breakdown["field_survey"]["explore_100m_passively"] == 300
    assert get_skill_xp(user, "bone_quarry") == 20


def test_profile_response_includes_skill_fields(session: Session) -> None:
    user = _make_user(session, username="prof", email="prof@example.com")
    award_site_discover_xp(user)
    session.add(user)
    session.commit()
    session.refresh(user)
    profile = user_to_profile_response(session, user)
    assert len(profile.skills) == 3
    site = next(s for s in profile.skills if s.id == "field_survey")
    assert site.xp == 20
    assert site.level == 1
    assert profile.career_title
    assert profile.career is not None
    assert profile.skill_breakdown["field_survey"]["discover_site"] == 20
    assert 0.0 <= profile.career.progress <= 1.0
