"""Site identification quiz (period + rock) after discovery."""

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
from app.services.level_service import (
    get_skill_xp,
    identification_xp_for_attempt,
)
from app.services.site_exploration_service import apply_site_exploration_update
from app.services.site_service.identify import (
    IDENTIFY_STEP_PERIOD,
    IDENTIFY_STEP_ROCK,
    get_identify_options,
    submit_identify_guess,
)
from app.services.site_service.list import get_site_by_id
from app.services.site_service.summary import site_row_to_summary
from app.services.site_service.site_type_fallback import load_site_types_by_period


def _make_user(session: Session, **kwargs) -> User:
    defaults = dict(
        username="identifier",
        email="identifier@example.com",
        password=User.hash_password("secret"),
    )
    defaults.update(kwargs)
    user = User(**defaults)
    session.add(user)
    session.commit()
    session.refresh(user)
    return user


def _ensure_site_types(session: Session) -> None:
    needed = [
        ("cretaceous", "sandstone"),
        ("cretaceous", "mudstone"),
        ("cretaceous", "shale"),
        ("jurassic", "sandstone"),
        ("triassic", "sandstone"),
    ]
    for period, rock in needed:
        existing = session.exec(
            select(SiteType).where(
                col(SiteType.period) == period,
                col(SiteType.rock_type) == rock,
            )
        ).first()
        if existing is None:
            session.add(SiteType(period=period, rock_type=rock))
    session.commit()


def _seed_field_site(session: Session, *, site_id: int = 1_000_000_801) -> Site:
    _ensure_site_types(session)
    site_type = session.exec(
        select(SiteType).where(
            col(SiteType.period) == "cretaceous",
            col(SiteType.rock_type) == "sandstone",
        )
    ).one()
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


def _discover(session: Session, *, user_id: int, site_id: int) -> UserSite:
    link = UserSite(
        user_id=user_id,
        site_id=site_id,
        role=USER_SITE_ROLE_DISCOVERER,
    )
    session.add(link)
    session.commit()
    session.refresh(link)
    return link


def test_identification_xp_for_attempt() -> None:
    assert identification_xp_for_attempt(base_xp=40, attempt=1) == 40
    assert identification_xp_for_attempt(base_xp=40, attempt=2) == 20
    assert identification_xp_for_attempt(base_xp=40, attempt=3) == 0


def test_redacts_period_until_identified(session: Session) -> None:
    user = _make_user(session)
    site = _seed_field_site(session)
    _discover(session, user_id=user.id, site_id=site.site_id)

    row = get_site_by_id(
        session,
        site.site_id,
        data_source=DATA_SOURCE_FIELD,
        viewer_user_id=user.id,
    )
    types = load_site_types_by_period(session)
    summary = site_row_to_summary(row, types_by_period=types)
    assert summary.viewer_has_identified is False
    assert summary.site_type_period is None
    assert summary.rock_type is None
    assert summary.odd_dino_band is None


def test_exploration_blocked_before_identification(session: Session) -> None:
    user = _make_user(session, username="blocked", email="blocked@example.com")
    site = _seed_field_site(session, site_id=1_000_000_802)
    link = _discover(session, user_id=user.id, site_id=site.site_id)

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
    assert link.explored_distance_m == 0.0
    assert get_skill_xp(user, "site_stewardship") == 0


def test_identify_wrong_then_right_awards_scaled_xp(session: Session) -> None:
    user = _make_user(session, username="quiz", email="quiz@example.com")
    site = _seed_field_site(session, site_id=1_000_000_803)
    _discover(session, user_id=user.id, site_id=site.site_id)

    options = get_identify_options(
        session, site_id=site.site_id, user_id=user.id
    )
    assert options.step == IDENTIFY_STEP_PERIOD
    assert set(options.choices) == {"triassic", "jurassic", "cretaceous"}

    wrong = submit_identify_guess(
        session,
        site_id=site.site_id,
        user=user,
        step=IDENTIFY_STEP_PERIOD,
        guess="jurassic",
    )
    assert wrong.correct is False
    assert wrong.message == "That doesn't look quite right"
    assert get_skill_xp(user, "site_stewardship") == 0

    right = submit_identify_guess(
        session,
        site_id=site.site_id,
        user=user,
        step=IDENTIFY_STEP_PERIOD,
        guess="cretaceous",
    )
    assert right.correct is True
    assert right.xp_awarded == 20  # second attempt → 50%
    assert right.period_identified is True
    assert right.identified is False
    assert get_skill_xp(user, "site_stewardship") == 20

    rock_opts = get_identify_options(
        session, site_id=site.site_id, user_id=user.id
    )
    assert rock_opts.step == IDENTIFY_STEP_ROCK
    assert "sandstone" in rock_opts.choices
    assert len(rock_opts.choices) == 4
    assert len(set(rock_opts.choices)) == 4

    done = submit_identify_guess(
        session,
        site_id=site.site_id,
        user=user,
        step=IDENTIFY_STEP_ROCK,
        guess="sandstone",
    )
    assert done.correct is True
    assert done.xp_awarded == 40  # first rock attempt
    assert done.identified is True
    assert done.site.viewer_has_identified is True
    assert done.site.status == "identified"
    assert done.site.identified_at is not None
    assert done.site.site_type_period == "cretaceous"
    assert done.site.rock_type == "sandstone"
    assert done.site.min_age_ma == 66.0
    assert done.site.max_age_ma == 145.0
    assert done.site.odd_dino_band is not None

    identifier = session.exec(
        select(UserSite).where(
            col(UserSite.user_id) == user.id,
            col(UserSite.site_id) == site.site_id,
            col(UserSite.role) == USER_SITE_ROLE_IDENTIFIER,
        )
    ).first()
    assert identifier is not None
    assert get_skill_xp(user, "site_stewardship") == 60


def test_identify_api_endpoints(client: TestClient, session: Session) -> None:
    registered = client.post(
        "/api/v1/auth/register",
        json={
            "username": "id_api",
            "email": "id_api@example.com",
            "password": "secret123",
            "full_name": "Dr. Id",
        },
    )
    assert registered.status_code == 201
    body = registered.json()
    headers = {"Authorization": f"Bearer {body['access_token']}"}
    user_id = body["user"]["id"]
    site = _seed_field_site(session, site_id=1_000_000_804)
    _discover(session, user_id=user_id, site_id=site.site_id)

    opts = client.get(
        f"/api/v1/sites/{site.site_id}/identify-options",
        headers=headers,
    )
    assert opts.status_code == 200
    assert opts.json()["step"] == "period"

    wrong = client.post(
        f"/api/v1/sites/{site.site_id}/identify",
        headers=headers,
        json={"step": "period", "guess": "triassic"},
    )
    assert wrong.status_code == 200
    assert wrong.json()["correct"] is False

    right = client.post(
        f"/api/v1/sites/{site.site_id}/identify",
        headers=headers,
        json={"step": "period", "guess": "cretaceous"},
    )
    assert right.status_code == 200
    assert right.json()["correct"] is True
    assert right.json()["xp_awarded"] == 20

    rock = client.post(
        f"/api/v1/sites/{site.site_id}/identify",
        headers=headers,
        json={"step": "rock_type", "guess": "sandstone"},
    )
    assert rock.status_code == 200
    payload = rock.json()
    assert payload["identified"] is True
    assert payload["site"]["viewer_has_identified"] is True
    assert payload["site"]["status"] == "identified"
    assert payload["site"]["identified_at"] is not None
    assert payload["site"]["site_type_period"] == "cretaceous"
