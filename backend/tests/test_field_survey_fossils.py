"""Tests for discovery-driven field fossil generation."""

from __future__ import annotations

import random
from decimal import Decimal

from sqlmodel import Session, col, select

from app.core.game_config import get_game_config
from app.core.security import create_access_token
from app.models.data_source import DATA_SOURCE_ARCHIVE, DATA_SOURCE_FIELD
from app.models.dinosaur_type import DinosaurType
from app.models.field_survey_job import FieldSurveyJob
from app.models.fossil import Fossil
from app.models.site import Site
from app.models.site_type import SiteType
from app.models.user import User
from app.models.user_fossil import USER_FOSSIL_ROLE_IN_SITU, UserFossil
from app.models.user_site import USER_SITE_ROLE_DISCOVERER, UserSite
from app.services.site_service.discover import discover_site
from app.services.field_service.field_fossil_generate import (
    FIELD_FOSSIL_ID_START,
    count_field_fossils_for_site,
    ensure_field_fossils_for_site,
    sample_depth_cm,
)
from app.services.field_service.field_fossil_onboard import (
    ensure_fossils_on_site_discovery,
)
from app.services.field_service.field_survey_queue import (
    STATUS_PENDING,
    claim_next_survey_job,
    enqueue_field_survey,
)
from app.workers.field_ensure_worker import process_one_survey_job


def _auth_headers(
    session: Session, *, username: str, email: str | None = None, is_admin: bool = False
) -> tuple[User, dict[str, str]]:
    user = User(
        username=username,
        email=email or f"{username}@example.com",
        password="x",
        is_admin=is_admin,
    )
    session.add(user)
    session.commit()
    session.refresh(user)
    token = create_access_token({"sub": str(user.id)})
    return user, {"Authorization": f"Bearer {token}"}


def _seed_archive_pool(session: Session) -> tuple[Site, list[DinosaurType]]:
    site_type = SiteType(period="cretaceous", rock_type="sandstone")
    session.add(site_type)
    session.commit()
    session.refresh(site_type)

    archive_site = Site(
        site_id=1001,
        latitude=Decimal("45.0"),
        longitude=Decimal("-110.0"),
        country_code="US",
        state="Montana",
        rock_type="sandstone",
        period="cretaceous",
        site_type_id=site_type.id,
        data_source=DATA_SOURCE_ARCHIVE,
    )
    session.add(archive_site)

    dinos: list[DinosaurType] = []
    for index, name in enumerate(("Tyrannosaurus", "Triceratops", "Edmontosaurus"), start=1):
        dino = DinosaurType(
            name=name,
            wikipedia_page_id=1000 + index,
            wikipedia_title=name,
            birth=70.0,
            death=66.0,
        )
        session.add(dino)
        dinos.append(dino)
    session.commit()
    for dino in dinos:
        session.refresh(dino)

    for index, dino in enumerate(dinos):
        for card in range(3):
            session.add(
                Fossil(
                    id=2000 + index * 10 + card,
                    dinosaur_id=dino.id,
                    site_id=archive_site.site_id,
                    identified_name=f"{dino.name} fossil {card}",
                    llm_imp_subcategory="teeth" if card % 2 == 0 else "skull",
                    llm_imp_completeness="fragmentary",
                    llm_imp_preservation_quality="moderate",
                    llm_imp_category="body",
                    llm_imp_rock_type="sandstone",
                    data_source=DATA_SOURCE_ARCHIVE,
                )
            )
    session.commit()
    return archive_site, dinos


def _seed_field_site(session: Session, *, site_id: int = 1_000_000_501) -> Site:
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


def test_sample_depth_cm_surface_bucket():
    get_game_config.cache_clear()
    buckets = get_game_config().fossil_generation.depth_buckets
    from app.core.game_config import FossilDepthBucket

    depth = sample_depth_cm(
        [FossilDepthBucket(weight=1.0, min_cm=0, max_cm=0)],
        score=0.0,
        rng=random.Random(1),
    )
    assert depth == 0
    depth_range = sample_depth_cm(
        [FossilDepthBucket(weight=1.0, min_cm=51, max_cm=200)],
        score=0.5,
        rng=random.Random(1),
    )
    assert 51 <= depth_range <= 200
    assert abs(sum(b.weight for b in buckets) - 1.0) < 1e-6


def test_ensure_field_fossils_zero_dino_stays_done(session: Session, monkeypatch):
    _seed_archive_pool(session)
    field_site = _seed_field_site(session, site_id=1_000_000_502)
    field_site.odd_dino_count = 0.05
    session.add(field_site)
    session.commit()

    from app.core.game_config import FossilOddNoiseConfig

    real_cfg = get_game_config().site_stewardship

    class _ZeroNoiseCfg:
        odd_noise = FossilOddNoiseConfig(
            dino_count=0.0,
            fossil_count=0.0,
            completeness=0.0,
            quality=0.0,
            depth=0.0,
        )
        dino_count = real_cfg.dino_count
        fossil_count = real_cfg.fossil_count
        depth_weights = real_cfg.depth_weights
        completeness_weights = real_cfg.completeness_weights
        quality_weights = real_cfg.quality_weights
        defaults = real_cfg.defaults

    monkeypatch.setattr(
        "app.services.field_service.field_fossil_generate._site_stewardship",
        lambda: _ZeroNoiseCfg(),
    )

    user = User(username="empty_disc", email="empty@example.com", password="x")
    session.add(user)
    session.commit()
    session.refresh(user)

    result = ensure_field_fossils_for_site(
        session, site_id=field_site.site_id, rng=random.Random(1)
    )
    assert not result.skipped
    assert result.generated == 0

    from app.services.field_service.field_survey_queue import (
        STATUS_DONE,
        mark_survey_job_done,
    )

    _, job = enqueue_field_survey(session, site_id=field_site.site_id, user_id=user.id)
    mark_survey_job_done(session, job, fossil_count=0)
    session.refresh(job)
    assert job.status == STATUS_DONE
    assert job.fossil_count == 0

    onboard = ensure_fossils_on_site_discovery(
        session, site_id=field_site.site_id, user_id=user.id
    )
    assert onboard.fossils_ready is True
    assert onboard.job_status == STATUS_DONE
    session.refresh(job)
    assert job.status == STATUS_DONE
    assert job.fossil_count == 0
    assert count_field_fossils_for_site(session, field_site.site_id) == 0


def test_ensure_field_fossils_samples_and_writes(session: Session):
    _seed_archive_pool(session)
    field_site = _seed_field_site(session)

    result = ensure_field_fossils_for_site(
        session, site_id=field_site.site_id, rng=random.Random(42)
    )
    assert not result.skipped
    assert result.generated >= 1

    fossils = session.exec(
        select(Fossil).where(
            col(Fossil.site_id) == field_site.site_id,
            col(Fossil.data_source) == DATA_SOURCE_FIELD,
        )
    ).all()
    assert len(fossils) == result.generated
    assert all(f.id >= FIELD_FOSSIL_ID_START for f in fossils)
    assert all(f.llm_imp_subcategory for f in fossils)
    assert all(f.depth_cm is not None and f.depth_cm >= 0 for f in fossils)

    by_dino: dict[int, list[str]] = {}
    for fossil in fossils:
        assert fossil.dinosaur_id is not None
        by_dino.setdefault(int(fossil.dinosaur_id), []).append(
            str(fossil.llm_imp_subcategory)
        )
    for subcats in by_dino.values():
        assert len(subcats) == len(set(subcats))

    again = ensure_field_fossils_for_site(
        session, site_id=field_site.site_id, rng=random.Random(99)
    )
    assert again.skipped
    assert again.generated == 0


def test_discover_multi_user_lazy_once(session: Session, monkeypatch):
    _seed_archive_pool(session)
    field_site = _seed_field_site(session)
    user_a = User(username="disc_a", email="a@example.com", password="x")
    user_b = User(username="disc_b", email="b@example.com", password="x")
    session.add(user_a)
    session.add(user_b)
    session.commit()
    session.refresh(user_a)
    session.refresh(user_b)

    monkeypatch.setattr(
        "app.services.site_service.discover.resolve_site_discovery_params",
        lambda *args, **kwargs: type(
            "P",
            (),
            {
                "max_distance_m": 50_000.0,
                "discovery_chance": 1.0,
                "base_discovery_chance": 1.0,
                "discover_site_xp": 20.0,
                "discover_site_as_first_xp": 20.0,
            },
        )(),
    )

    first = discover_site(
        session,
        site_id=field_site.site_id,
        user_id=user_a.id,
        lat=40.0,
        lon=-100.0,
        rng=random.Random(1),
    )
    assert first.job_id is not None
    assert first.fossils_ready is False
    assert first.generated is True

    second = discover_site(
        session,
        site_id=field_site.site_id,
        user_id=user_b.id,
        lat=40.0,
        lon=-100.0,
        rng=random.Random(1),
    )
    assert second.job_id == first.job_id
    assert second.onboarded is True
    assert second.fossils_ready is False

    discoverers = session.exec(
        select(UserSite).where(
            col(UserSite.site_id) == field_site.site_id,
            col(UserSite.role) == USER_SITE_ROLE_DISCOVERER,
        )
    ).all()
    assert {row.user_id for row in discoverers} == {user_a.id, user_b.id}

    jobs = session.exec(select(FieldSurveyJob)).all()
    assert len(jobs) == 1
    assert jobs[0].status == STATUS_PENDING

    assert process_one_survey_job(worker_id="test-worker") is True

    fossils = session.exec(
        select(Fossil).where(
            col(Fossil.site_id) == field_site.site_id,
            col(Fossil.data_source) == DATA_SOURCE_FIELD,
        )
    ).all()
    assert len(fossils) >= 1

    surface_ids = {f.id for f in fossils if f.depth_cm == 0}
    for user in (user_a, user_b):
        links = session.exec(
            select(UserFossil).where(
                col(UserFossil.user_id) == user.id,
                col(UserFossil.role) == USER_FOSSIL_ROLE_IN_SITU,
            )
        ).all()
        # Discovery no longer creates user_fossil; extraction does that later.
        assert links == []
        discoverer = session.exec(
            select(UserSite).where(
                col(UserSite.user_id) == user.id,
                col(UserSite.site_id) == field_site.site_id,
                col(UserSite.role) == USER_SITE_ROLE_DISCOVERER,
            )
        ).one()
        session.refresh(user)
        if surface_ids:
            assert discoverer.locate_in_situ_awarded is True
            expected_xp = 20 * len(surface_ids)
            assert (
                user.skill_breakdown["bone_quarry"]["locate_fossil_in_situ"]
                == expected_xp
            )
        else:
            assert discoverer.locate_in_situ_awarded is False

    third = ensure_fossils_on_site_discovery(
        session, site_id=field_site.site_id, user_id=user_a.id
    )
    assert third.fossils_ready is True
    assert third.generated is False
    assert set(third.surface_fossil_ids) == surface_ids
    # Idempotent: XP not awarded twice.
    if surface_ids:
        session.refresh(user_a)
        assert user_a.skill_breakdown["bone_quarry"]["locate_fossil_in_situ"] == (
            20 * len(surface_ids)
        )


def test_enqueue_onboards_active_job(session: Session):
    _seed_archive_pool(session)
    field_site = _seed_field_site(session, site_id=1_000_000_502)
    user_a = User(username="q_a", email="qa@example.com", password="x")
    user_b = User(username="q_b", email="qb@example.com", password="x")
    session.add(user_a)
    session.add(user_b)
    session.commit()
    session.refresh(user_a)
    session.refresh(user_b)

    accepted_a, job_a = enqueue_field_survey(
        session, site_id=field_site.site_id, user_id=user_a.id
    )
    accepted_b, job_b = enqueue_field_survey(
        session, site_id=field_site.site_id, user_id=user_b.id
    )
    assert accepted_a is True
    assert accepted_b is False
    assert job_a.id == job_b.id

    claimed = claim_next_survey_job(session, worker_id="w1")
    assert claimed is not None
    assert claimed.id == job_a.id


def test_discover_api_and_visibility(client, session: Session, monkeypatch):
    _seed_archive_pool(session)
    field_site = _seed_field_site(session, site_id=1_000_000_503)
    user, headers = _auth_headers(session, username="disc_api")
    _admin, admin_headers = _auth_headers(
        session, username="disc_admin", is_admin=True
    )

    monkeypatch.setattr(
        "app.services.site_service.discover.resolve_site_discovery_params",
        lambda *args, **kwargs: type(
            "P",
            (),
            {
                "max_distance_m": 50_000.0,
                "discovery_chance": 1.0,
                "base_discovery_chance": 1.0,
                "discover_site_xp": 20.0,
                "discover_site_as_first_xp": 20.0,
            },
        )(),
    )

    response = client.post(
        f"/api/v1/sites/{field_site.site_id}/discover",
        headers=headers,
        json={"lat": 40.0, "lon": -100.0},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["site"]["status"] == "discovered"
    assert body["fossils_ready"] is False
    assert body["job_id"] is not None

    assert process_one_survey_job(worker_id="api-test") is True

    job = client.get(
        f"/api/v1/sites/survey/jobs/{body['job_id']}",
        headers=headers,
    )
    assert job.status_code == 200
    assert job.json()["status"] == "done"
    assert (job.json()["fossil_count"] or 0) >= 1

    # Re-hit discover to collect surface fossils for this user (idempotent).
    again = client.post(
        f"/api/v1/sites/{field_site.site_id}/discover",
        headers=headers,
        json={"lat": 40.0, "lon": -100.0},
    )
    assert again.status_code == 200
    again_body = again.json()
    assert again_body["fossils_ready"] is True

    fossils = client.get(
        f"/api/v1/sites/{field_site.site_id}/fossils",
        headers=headers,
    )
    assert fossils.status_code == 200
    # Discoverer sees depth-0 in-situ fossils without a user_fossil link.
    assert len(fossils.json()["items"]) == len(again_body["surface_fossils"])
    assert all(item["status"] == "in_situ" for item in fossils.json()["items"])

    # Collection catalog stays empty until the user extracts (user_fossil).
    catalog = client.get(
        "/api/v1/fossils",
        params={"data_source": "field"},
        headers=headers,
    )
    assert catalog.status_code == 200
    assert catalog.json()["total"] == 0

    admin_catalog = client.get(
        "/api/v1/fossils",
        params={"data_source": "field"},
        headers=admin_headers,
    )
    assert admin_catalog.status_code == 200
    # Catalog is linked-only for admins too (no include_hidden).
    assert admin_catalog.json()["total"] == 0

    admin_site = client.get(
        f"/api/v1/sites/{field_site.site_id}/fossils",
        headers=admin_headers,
    )
    assert admin_site.status_code == 200
    # Admin without discoverer link / user_fossil sees nothing without include_hidden.
    assert len(admin_site.json()["items"]) == 0

    admin_peek = client.get(
        f"/api/v1/sites/{field_site.site_id}/fossils",
        params={"include_hidden": "true"},
        headers=admin_headers,
    )
    assert admin_peek.status_code == 200
    assert len(admin_peek.json()["items"]) >= len(fossils.json()["items"])
    statuses = {item["status"] for item in admin_peek.json()["items"]}
    assert "hidden" in statuses or "in_situ" in statuses

    denied = client.get(
        f"/api/v1/sites/{field_site.site_id}/fossils",
        params={"include_hidden": "true"},
        headers=headers,
    )
    assert denied.status_code == 400
