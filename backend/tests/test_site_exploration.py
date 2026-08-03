"""Site exploration XP, accuracy boost, and sync API."""

from __future__ import annotations

from decimal import Decimal

from fastapi.testclient import TestClient
from sqlmodel import Session, col, select

from app.models.data_source import DATA_SOURCE_FIELD
from app.models.site import Site
from app.models.site_type import SiteType
from app.models.user import User
from app.models.user_site import USER_SITE_ROLE_DISCOVERER, UserSite
from app.schemas.site import SiteExplorationEntry, SiteExplorationUpdateRequest
from app.services.level_service import (
    award_site_exploration_xp,
    exploration_batch_count,
    get_skill_xp,
)
from app.services.site_exploration_service import apply_site_exploration_update
from app.services.site_service.dimension_display import (
    apply_exploration_accuracy_boost,
    build_site_dimension_bands,
    SiteDimensionKey,
)
from app.services.site_service.summary import SiteRow, site_row_to_summary


def _make_user(session: Session, **kwargs) -> User:
    defaults = dict(
        username="explorer",
        email="explorer@example.com",
        password=User.hash_password("secret"),
    )
    defaults.update(kwargs)
    user = User(**defaults)
    session.add(user)
    session.commit()
    session.refresh(user)
    return user


def _seed_field_site(session: Session, *, site_id: int = 1_000_000_701) -> Site:
    site_type = session.exec(
        select(SiteType).where(
            col(SiteType.period) == "cretaceous",
            col(SiteType.rock_type) == "sandstone",
        )
    ).first()
    if site_type is None:
        site_type = SiteType(period="cretaceous", rock_type="sandstone")
        session.add(site_type)
        session.commit()
        session.refresh(site_type)

    site = Site(
        site_id=site_id,
        latitude=Decimal("40.000000"),
        longitude=Decimal("-100.000000"),
        country_code="US",
        state="Montana",
        rock_type="sandstone",
        period="cretaceous",
        site_type_id=site_type.id,
        data_source=DATA_SOURCE_FIELD,
        odd_dino_count=0.7,
        odd_fossil_count=0.5,
        odd_completeness=0.5,
        odd_quality=0.5,
        odd_depth=0.3,
    )
    session.add(site)
    session.commit()
    session.refresh(site)
    return site


def test_exploration_batch_count() -> None:
    assert exploration_batch_count(0) == 0
    assert exploration_batch_count(19.9) == 0
    assert exploration_batch_count(20) == 1
    assert exploration_batch_count(39.9) == 1
    assert exploration_batch_count(40) == 2


def test_award_site_exploration_xp_batches(session: Session) -> None:
    user = _make_user(session)
    awarded = award_site_exploration_xp(
        user,
        previous_explored_m=0,
        new_explored_m=45,
    )
    session.add(user)
    session.commit()
    session.refresh(user)
    # floor(45/20) - floor(0/20) = 2 batches × 20 XP
    assert awarded == 40
    assert get_skill_xp(user, "site_stewardship") == 40
    assert user.skill_breakdown["site_stewardship"]["site_exploration"] == 40

    awarded2 = award_site_exploration_xp(
        user,
        previous_explored_m=45,
        new_explored_m=55,
    )
    session.add(user)
    session.commit()
    session.refresh(user)
    # floor(55/20) - floor(45/20) = 2 - 2 = 0
    assert awarded2 == 0
    assert get_skill_xp(user, "site_stewardship") == 40

    awarded3 = award_site_exploration_xp(
        user,
        previous_explored_m=55,
        new_explored_m=60,
    )
    session.add(user)
    session.commit()
    session.refresh(user)
    assert awarded3 == 20
    assert get_skill_xp(user, "site_stewardship") == 60


def test_apply_exploration_accuracy_boost() -> None:
    assert apply_exploration_accuracy_boost(0.01, 0) == 0.01
    assert apply_exploration_accuracy_boost(0.01, 10) == 0.11
    assert apply_exploration_accuracy_boost(0.5, 100) == 1.0
    assert apply_exploration_accuracy_boost(0.99, 5) == 1.0


def test_build_bands_apply_explored_boost() -> None:
    baseline = build_site_dimension_bands(
        site_id=1,
        odd_dino_count=0.5,
        odd_fossil_count=0.5,
        odd_completeness=0.5,
        odd_quality=0.5,
        odd_depth=0.5,
        skill_level=1,
        explored_distance_m=0.0,
    )
    boosted = build_site_dimension_bands(
        site_id=1,
        odd_dino_count=0.5,
        odd_fossil_count=0.5,
        odd_completeness=0.5,
        odd_quality=0.5,
        odd_depth=0.5,
        skill_level=1,
        explored_distance_m=50.0,
    )
    assert baseline[SiteDimensionKey.DINO] is not None
    assert boosted[SiteDimensionKey.DINO] is not None
    assert (
        boosted[SiteDimensionKey.DINO].effective_accuracy
        > baseline[SiteDimensionKey.DINO].effective_accuracy
    )
    # Exploration adds a flat +0.50 regardless of per-axis noise.
    assert abs(
        boosted[SiteDimensionKey.DINO].effective_accuracy
        - baseline[SiteDimensionKey.DINO].effective_accuracy
        - 0.50
    ) < 1e-6


def test_site_row_to_summary_includes_explored_distance() -> None:
    site = Site(
        site_id=900002,
        odd_dino_count=0.42,
        odd_fossil_count=0.55,
        odd_completeness=0.61,
        odd_quality=0.33,
        odd_depth=0.78,
    )
    summary = site_row_to_summary(
        SiteRow(site=site, site_type=None, explored_distance_m=30.0)
    )
    assert summary.explored_distance_m == 30.0
    assert summary.odd_dino_band is not None
    # L1 baseline (~0.01) ± noise + 0.30 exploration.
    assert 0.30 <= summary.odd_dino_band.effective_accuracy <= 0.61
    assert summary.documented is None


def test_documentation_completes_and_freezes(session: Session) -> None:
    from app.services.level_service.skills import set_skill_xp
    from app.services.level_service.xp_table import SKILL_THRESHOLDS

    user = _make_user(session, username="doc", email="doc@example.com")
    # High stewardship level so less walking is needed to hit 100%.
    set_skill_xp(user, "site_stewardship", SKILL_THRESHOLDS[90])
    session.add(user)
    session.commit()
    session.refresh(user)

    site = _seed_field_site(session, site_id=1_000_000_777)
    link = UserSite(
        user_id=user.id,
        site_id=site.site_id,
        role=USER_SITE_ROLE_DISCOVERER,
        explored_distance_m=0.0,
    )
    session.add(link)
    session.commit()

    # Plenty of meters to clear ±30 pt noise even from a low roll.
    profile, summaries = apply_site_exploration_update(
        session,
        user,
        SiteExplorationUpdateRequest(
            sites=[
                SiteExplorationEntry(
                    site_id=site.site_id,
                    explored_distance_m=80.0,
                )
            ]
        ),
    )
    session.refresh(link)
    assert link.documented is True
    assert link.explored_distance_m == 80.0
    assert summaries[0].documented is True
    assert summaries[0].viewer_has_documented is True
    assert summaries[0].status == "documented"
    doc_role = session.exec(
        select(UserSite).where(
            col(UserSite.user_id) == user.id,
            col(UserSite.site_id) == site.site_id,
            col(UserSite.role) == "documenter",
        )
    ).first()
    assert doc_role is not None
    assert profile.skill_breakdown["site_stewardship"]["site_documentation"] == 100

    xp_after = get_skill_xp(user, "site_stewardship")
    apply_site_exploration_update(
        session,
        user,
        SiteExplorationUpdateRequest(
            sites=[
                SiteExplorationEntry(
                    site_id=site.site_id,
                    explored_distance_m=200.0,
                )
            ]
        ),
    )
    session.refresh(link)
    assert link.explored_distance_m == 80.0
    assert get_skill_xp(user, "site_stewardship") == xp_after
    assert (
        user.skill_breakdown["site_stewardship"]["site_documentation"] == 100
    )


def test_apply_site_exploration_update_monotonic_resume(session: Session) -> None:
    user = _make_user(session, username="resume", email="resume@example.com")
    site = _seed_field_site(session)
    link = UserSite(
        user_id=user.id,
        site_id=site.site_id,
        role=USER_SITE_ROLE_DISCOVERER,
        explored_distance_m=30.0,
    )
    session.add(link)
    session.commit()

    profile, summaries = apply_site_exploration_update(
        session,
        user,
        SiteExplorationUpdateRequest(
            sites=[
                SiteExplorationEntry(
                    site_id=site.site_id,
                    explored_distance_m=50.0,
                )
            ]
        ),
    )
    session.refresh(link)
    assert link.explored_distance_m == 50.0
    # floor(50/20) - floor(30/20) = 2 - 1 = 1 batch × 20
    assert get_skill_xp(user, "site_stewardship") == 20
    assert len(summaries) == 1
    assert summaries[0].explored_distance_m == 50.0
    assert profile.skill_breakdown["site_stewardship"]["site_exploration"] == 20

    # Downward report ignored; no extra XP.
    apply_site_exploration_update(
        session,
        user,
        SiteExplorationUpdateRequest(
            sites=[
                SiteExplorationEntry(
                    site_id=site.site_id,
                    explored_distance_m=40.0,
                )
            ]
        ),
    )
    session.refresh(link)
    assert link.explored_distance_m == 50.0
    assert get_skill_xp(user, "site_stewardship") == 20


def _register_user(client: TestClient, username: str, email: str) -> dict:
    response = client.post(
        "/api/v1/auth/register",
        json={
            "username": username,
            "email": email,
            "password": "secret123",
            "full_name": "Dr. Explore",
        },
    )
    assert response.status_code == 201
    return response.json()


def test_patch_site_exploration_api(
    client: TestClient, session: Session
) -> None:
    registered = _register_user(client, "api_explore", "api_explore@example.com")
    headers = {"Authorization": f"Bearer {registered['access_token']}"}
    user_id = registered["user"]["id"]
    site = _seed_field_site(session, site_id=1_000_000_702)
    session.add(
        UserSite(
            user_id=user_id,
            site_id=site.site_id,
            role=USER_SITE_ROLE_DISCOVERER,
        )
    )
    session.commit()

    response = client.patch(
        "/api/v1/users/me/site-exploration",
        headers=headers,
        json={
            "sites": [
                {"site_id": site.site_id, "explored_distance_m": 25.0},
            ]
        },
    )
    assert response.status_code == 200
    body = response.json()
    assert body["profile"]["skill_breakdown"]["site_stewardship"][
        "site_exploration"
    ] == 20
    assert len(body["sites"]) == 1
    assert body["sites"][0]["explored_distance_m"] == 25.0
    assert body["sites"][0]["odd_dino_band"] is not None
