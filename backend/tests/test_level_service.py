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
    award_distance_km_xp,
    award_fossil_discover_xp,
    award_site_discover_xp,
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
    assert site.site_discovery_xp == 10
    assert site.active_km_xp == 30
    assert site.passive_km_xp == 5
    assert float(fossil.main_params["fossil_discovery_xp"]) == 5
    assert len(cfg.skills) == 12
    assert cfg.skills[0].id == "site_discovery"
    assert cfg.skills[1].id == "site_survey"
    assert cfg.skills[2].id == "site_clearing"
    assert cfg.skills[3].id == "fossil_detection"
    assert cfg.skills[4].id == "fossil_excavation"
    assert cfg.skills[6].id == "fossil_curation"
    assert cfg.skills[7].id == "fossil_preparation"
    assert cfg.skills[8].id == "fossil_analysis"
    assert cfg.skills[9].id == "dinosaur_modelling"
    assert cfg.skills[10].id == "dinosaur_mounting"
    assert cfg.skills[11].id == "academic_publishing"
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
    award_fossil_discover_xp(user, count=2)
    session.add(user)
    session.commit()
    session.refresh(user)
    assert get_skill_xp(user, "site_discovery") == 10
    assert get_skill_xp(user, "fossil_detection") == 10
    assert user.skill_breakdown["site_discovery"]["sites"] == 10
    assert user.skill_breakdown["fossil_detection"]["fossils"] == 10
    assert user.xp == 20
    assert user.level == level_for_xp(user.xp, career=True)


def test_award_distance_km_xp(session: Session) -> None:
    user = _make_user(session)
    award_distance_km_xp(user, active_km_delta=2, passive_km_delta=3)
    session.add(user)
    session.commit()
    session.refresh(user)
    breakdown = user.skill_breakdown["site_discovery"]
    assert breakdown["active_distance"] == 60
    assert breakdown["passive_distance"] == 15
    assert get_skill_xp(user, "site_discovery") == 75


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
    breakdown = user.skill_breakdown["site_discovery"]
    assert breakdown["active_distance"] == 30
    assert breakdown["passive_distance"] == 5
    assert get_skill_xp(user, "site_discovery") == 35

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
    breakdown = user.skill_breakdown["site_discovery"]
    assert breakdown["active_distance"] == 60
    assert breakdown["passive_distance"] == 5
    assert get_skill_xp(user, "site_discovery") == 65


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
    assert user.skill_xp["site_discovery"] == skill_xp["site_discovery"]
    assert user.skill_xp["fossil_detection"] == skill_xp["fossil_detection"]
    assert user.skill_breakdown["site_discovery"]["sites"] == 20
    assert user.skill_breakdown["fossil_detection"]["fossils"] == 5
    assert user.skill_breakdown["site_discovery"]["active_distance"] == 60
    assert user.skill_breakdown["site_discovery"]["passive_distance"] == 15
    assert get_skill_xp(user, "fossil_excavation") == 0


def test_profile_response_includes_skill_fields(session: Session) -> None:
    user = _make_user(session, username="prof", email="prof@example.com")
    award_site_discover_xp(user)
    session.add(user)
    session.commit()
    session.refresh(user)
    profile = user_to_profile_response(session, user)
    assert len(profile.skills) == 12
    site = next(s for s in profile.skills if s.id == "site_discovery")
    assert site.xp == 10
    assert site.level == 1
    assert profile.career_title
    assert profile.career is not None
    assert profile.skill_breakdown["site_discovery"]["sites"] == 10
    assert 0.0 <= profile.career.progress <= 1.0
