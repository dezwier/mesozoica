"""Time-based site documentation progress and sync API."""

from __future__ import annotations

from decimal import Decimal

from fastapi.testclient import TestClient
from sqlmodel import Session, col, select

from app.models.data_source import DATA_SOURCE_FIELD
from app.models.site import Site
from app.models.site_type import SiteType
from app.models.user import User
from app.models.user_site import (
    USER_SITE_ROLE_DISCOVERER,
    USER_SITE_ROLE_IDENTIFIER,
    UserSite,
)
from app.schemas.site import SiteExplorationEntry, SiteExplorationUpdateRequest
from app.services.level_service import get_skill_xp
from app.services.site_exploration_service import apply_site_exploration_update
from app.services.site_service.dimension_display import (
    apply_documentation_progress,
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


def _discovered_identified(
    session: Session,
    *,
    user_id: int,
    site_id: int,
    documentation_progress: float = 0.0,
) -> UserSite:
    """Discoverer row with identification complete."""
    link = UserSite(
        user_id=user_id,
        site_id=site_id,
        role=USER_SITE_ROLE_DISCOVERER,
        documentation_progress=documentation_progress,
        period_identified=True,
        rock_identified=True,
    )
    session.add(link)
    session.add(
        UserSite(
            user_id=user_id,
            site_id=site_id,
            role=USER_SITE_ROLE_IDENTIFIER,
        )
    )
    session.commit()
    session.refresh(link)
    return link


def test_apply_documentation_progress() -> None:
    assert apply_documentation_progress(0.01, 0) == 0.01
    assert apply_documentation_progress(0.01, 0.1) == 0.11
    assert apply_documentation_progress(0.5, 1) == 1.0
    assert apply_documentation_progress(0.99, 0.05) == 1.0


def test_build_bands_apply_documentation_progress() -> None:
    baseline = build_site_dimension_bands(
        site_id=1,
        odd_dino_count=0.5,
        odd_fossil_count=0.5,
        odd_completeness=0.5,
        odd_quality=0.5,
        odd_depth=0.5,
        skill_level=1,
        documentation_progress=0.0,
    )
    boosted = build_site_dimension_bands(
        site_id=1,
        odd_dino_count=0.5,
        odd_fossil_count=0.5,
        odd_completeness=0.5,
        odd_quality=0.5,
        odd_depth=0.5,
        skill_level=1,
        documentation_progress=0.5,
    )
    assert baseline[SiteDimensionKey.DINO] is not None
    assert boosted[SiteDimensionKey.DINO] is not None
    assert (
        boosted[SiteDimensionKey.DINO].effective_accuracy
        > baseline[SiteDimensionKey.DINO].effective_accuracy
    )
    # Documentation adds a flat +0.50 regardless of per-axis noise.
    assert abs(
        boosted[SiteDimensionKey.DINO].effective_accuracy
        - baseline[SiteDimensionKey.DINO].effective_accuracy
        - 0.50
    ) < 1e-6


def test_site_row_to_summary_includes_documentation_progress() -> None:
    site = Site(
        site_id=900002,
        odd_dino_count=0.42,
        odd_fossil_count=0.55,
        odd_completeness=0.61,
        odd_quality=0.33,
        odd_depth=0.78,
    )
    summary = site_row_to_summary(
        SiteRow(site=site, site_type=None, documentation_progress=0.3)
    )
    assert summary.documentation_progress == 0.3
    assert summary.odd_dino_band is not None
    # L1 baseline (~0.01) ± noise + 0.30 documentation.
    assert 0.30 <= summary.odd_dino_band.effective_accuracy <= 0.61
    assert summary.documented is None


def test_documentation_completes_and_freezes(
    session: Session, monkeypatch
) -> None:
    from app.services.level_service.skills import set_skill_xp
    from app.services.level_service.xp_table import SKILL_THRESHOLDS

    pushes: list[dict] = []

    def _fake_push(session, **kwargs):
        pushes.append(kwargs)

    monkeypatch.setattr(
        "app.features.accounts.application.celebrations.send_site_celebration_push",
        _fake_push,
    )

    user = _make_user(session, username="doc", email="doc@example.com")
    # High stewardship level means less timed progress is needed to hit 100%.
    set_skill_xp(user, "field_survey", SKILL_THRESHOLDS[90])
    session.add(user)
    session.commit()
    session.refresh(user)

    site = _seed_field_site(session, site_id=1_000_000_777)
    link = _discovered_identified(
        session, user_id=user.id, site_id=site.site_id
    )

    # Full progress clears ±30 pt noise even from a low roll.
    celebrations = []
    profile, summaries = apply_site_exploration_update(
        session,
        user,
        SiteExplorationUpdateRequest(
            sites=[
                SiteExplorationEntry(
                    site_id=site.site_id,
                    documentation_progress=1.0,
                )
            ]
        ),
        celebrations_out=celebrations,
    )
    session.refresh(link)
    assert link.documented is True
    assert link.documentation_progress == 1.0
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
    assert doc_role.was_first is True
    assert summaries[0].viewer_was_first_documentation is True
    assert summaries[0].documented_at is not None
    assert profile.skill_breakdown["field_survey"]["document_site"] == 20
    assert profile.skill_breakdown["field_survey"]["document_site_as_first"] == 20

    from app.models.user_notification import UserNotification, UserNotificationType

    assert len(celebrations) == 1
    assert celebrations[0].type == UserNotificationType.SITE_DOCUMENTED
    assert celebrations[0].site_id == site.site_id

    notif = session.exec(
        select(UserNotification).where(
            col(UserNotification.user_id) == user.id,
            col(UserNotification.type) == UserNotificationType.SITE_DOCUMENTED,
            col(UserNotification.site_id) == site.site_id,
        )
    ).first()
    assert notif is not None
    assert len(pushes) == 1
    assert pushes[0]["site_id"] == site.site_id
    assert pushes[0]["notification_id"] == notif.id

    xp_after = get_skill_xp(user, "field_survey")
    apply_site_exploration_update(
        session,
        user,
        SiteExplorationUpdateRequest(
            sites=[
                SiteExplorationEntry(
                    site_id=site.site_id,
                    documentation_progress=1.0,
                )
            ]
        ),
    )
    session.refresh(link)
    assert link.documentation_progress == 1.0
    assert get_skill_xp(user, "field_survey") == xp_after
    assert (
        user.skill_breakdown["field_survey"]["document_site"] == 20
    )
    assert (
        user.skill_breakdown["field_survey"]["document_site_as_first"] == 20
    )
    # Frozen re-sync does not create another notification/push.
    assert len(pushes) == 1
    notif_count = session.exec(
        select(UserNotification).where(
            col(UserNotification.user_id) == user.id,
            col(UserNotification.type) == UserNotificationType.SITE_DOCUMENTED,
            col(UserNotification.site_id) == site.site_id,
        )
    ).all()
    assert len(notif_count) == 1


def test_second_documenter_skips_document_site_as_first_xp(
    session: Session, monkeypatch
) -> None:
    from app.services.level_service.skills import set_skill_xp
    from app.services.level_service.xp_table import SKILL_THRESHOLDS

    monkeypatch.setattr(
        "app.features.accounts.application.celebrations.send_site_celebration_push",
        lambda *args, **kwargs: None,
    )

    first = _make_user(session, username="doc1", email="doc1@example.com")
    second = _make_user(session, username="doc2", email="doc2@example.com")
    set_skill_xp(first, "field_survey", SKILL_THRESHOLDS[90])
    set_skill_xp(second, "field_survey", SKILL_THRESHOLDS[90])
    session.add(first)
    session.add(second)
    session.commit()
    session.refresh(first)
    session.refresh(second)

    site = _seed_field_site(session, site_id=1_000_000_778)
    for user in (first, second):
        _discovered_identified(
            session, user_id=user.id, site_id=site.site_id
        )

    apply_site_exploration_update(
        session,
        first,
        SiteExplorationUpdateRequest(
            sites=[
                SiteExplorationEntry(
                    site_id=site.site_id,
                    documentation_progress=1.0,
                )
            ]
        ),
    )
    assert first.skill_breakdown["field_survey"]["document_site"] == 20
    assert first.skill_breakdown["field_survey"]["document_site_as_first"] == 20

    apply_site_exploration_update(
        session,
        second,
        SiteExplorationUpdateRequest(
            sites=[
                SiteExplorationEntry(
                    site_id=site.site_id,
                    documentation_progress=1.0,
                )
            ]
        ),
    )
    assert second.skill_breakdown["field_survey"]["document_site"] == 20
    assert "document_site_as_first" not in (
        second.skill_breakdown.get("field_survey") or {}
    )
    second_doc = session.exec(
        select(UserSite).where(
            col(UserSite.user_id) == second.id,
            col(UserSite.site_id) == site.site_id,
            col(UserSite.role) == "documenter",
        )
    ).one()
    assert second_doc.was_first is False


def test_apply_site_exploration_update_monotonic_resume(session: Session) -> None:
    user = _make_user(session, username="resume", email="resume@example.com")
    site = _seed_field_site(session)
    link = _discovered_identified(
        session,
        user_id=user.id,
        site_id=site.site_id,
        documentation_progress=0.3,
    )

    profile, summaries = apply_site_exploration_update(
        session,
        user,
        SiteExplorationUpdateRequest(
            sites=[
                SiteExplorationEntry(
                    site_id=site.site_id,
                    documentation_progress=0.5,
                )
            ]
        ),
    )
    session.refresh(link)
    assert link.documentation_progress == 0.5
    assert get_skill_xp(user, "field_survey") == 0
    assert len(summaries) == 1
    assert summaries[0].documentation_progress == 0.5
    assert "document_progress" not in (
        profile.skill_breakdown.get("field_survey") or {}
    )

    # Downward report ignored; no extra XP.
    apply_site_exploration_update(
        session,
        user,
        SiteExplorationUpdateRequest(
            sites=[
                SiteExplorationEntry(
                    site_id=site.site_id,
                    documentation_progress=0.4,
                )
            ]
        ),
    )
    session.refresh(link)
    assert link.documentation_progress == 0.5
    assert get_skill_xp(user, "field_survey") == 0


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


def test_patch_document_progress_api(
    client: TestClient, session: Session
) -> None:
    registered = _register_user(client, "api_explore", "api_explore@example.com")
    headers = {"Authorization": f"Bearer {registered['access_token']}"}
    user_id = registered["user"]["id"]
    site = _seed_field_site(session, site_id=1_000_000_702)
    _discovered_identified(session, user_id=user_id, site_id=site.site_id)

    response = client.patch(
        "/api/v1/users/me/site-exploration",
        headers=headers,
        json={
            "sites": [
                {"site_id": site.site_id, "documentation_progress": 0.25},
            ]
        },
    )
    assert response.status_code == 200
    body = response.json()
    assert "document_progress" not in (
        body["profile"]["skill_breakdown"].get("field_survey") or {}
    )
    assert len(body["sites"]) == 1
    assert body["sites"][0]["documentation_progress"] == 0.25
    assert body["sites"][0]["odd_dino_band"] is not None
    assert body["celebrations"] == []
