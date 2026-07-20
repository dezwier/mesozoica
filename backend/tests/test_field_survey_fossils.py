"""Tests for survey-driven field fossil generation."""

from __future__ import annotations

import random
from decimal import Decimal

from sqlmodel import Session, col, select

from app.core.security import create_access_token
from app.models.data_source import DATA_SOURCE_ARCHIVE, DATA_SOURCE_FIELD
from app.models.dinosaur import Dinosaur
from app.models.field_survey_job import FieldSurveyJob
from app.models.fossil import Fossil
from app.models.site import Site
from app.models.site_type import SiteType
from app.models.user import User
from app.models.user_site import USER_SITE_ROLE_SURVEYOR, UserSite
from app.services.site_service.field_fossil_generate import (
    FIELD_FOSSIL_ID_START,
    ensure_field_fossils_for_site,
)
from app.services.site_service.field_survey_queue import (
    STATUS_PENDING,
    claim_next_survey_job,
    enqueue_field_survey,
)
from app.services.site_service.survey import survey_site
from app.workers.field_ensure_worker import process_one_survey_job


def _auth_headers(session: Session, *, username: str, email: str | None = None) -> tuple[User, dict[str, str]]:
    user = User(
        username=username,
        email=email or f"{username}@example.com",
        password="x",
    )
    session.add(user)
    session.commit()
    session.refresh(user)
    token = create_access_token({"sub": str(user.id)})
    return user, {"Authorization": f"Bearer {token}"}


def _seed_archive_pool(session: Session) -> tuple[Site, list[Dinosaur]]:
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

    dinos: list[Dinosaur] = []
    for index, name in enumerate(("Tyrannosaurus", "Triceratops", "Edmontosaurus"), start=1):
        dino = Dinosaur(
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
    )
    session.add(site)
    session.commit()
    session.refresh(site)
    return site


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

    again = ensure_field_fossils_for_site(
        session, site_id=field_site.site_id, rng=random.Random(99)
    )
    assert again.skipped
    assert again.generated == 0


def test_survey_multi_user_lazy_once(session: Session):
    _seed_archive_pool(session)
    field_site = _seed_field_site(session)
    user_a = User(username="survey_a", email="a@example.com", password="x")
    user_b = User(username="survey_b", email="b@example.com", password="x")
    session.add(user_a)
    session.add(user_b)
    session.commit()
    session.refresh(user_a)
    session.refresh(user_b)

    first = survey_site(session, site_id=field_site.site_id, user_id=user_a.id)
    assert first.job_id is not None
    assert first.fossils_ready is False
    assert first.generated is True

    second = survey_site(session, site_id=field_site.site_id, user_id=user_b.id)
    assert second.job_id == first.job_id
    assert second.onboarded is True
    assert second.fossils_ready is False

    surveyors = session.exec(
        select(UserSite).where(
            col(UserSite.site_id) == field_site.site_id,
            col(UserSite.role) == USER_SITE_ROLE_SURVEYOR,
        )
    ).all()
    assert {row.user_id for row in surveyors} == {user_a.id, user_b.id}

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

    third = survey_site(session, site_id=field_site.site_id, user_id=user_a.id)
    assert third.fossils_ready is True
    assert third.generated is False
    assert len(
        session.exec(
            select(Fossil).where(
                col(Fossil.site_id) == field_site.site_id,
                col(Fossil.data_source) == DATA_SOURCE_FIELD,
            )
        ).all()
    ) == len(fossils)


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


def test_survey_api_and_fossils_endpoint(client, session: Session):
    _seed_archive_pool(session)
    field_site = _seed_field_site(session, site_id=1_000_000_503)
    _user, headers = _auth_headers(session, username="survey_api")

    response = client.post(
        f"/api/v1/sites/{field_site.site_id}/survey",
        headers=headers,
    )
    assert response.status_code == 200
    body = response.json()
    assert body["site"]["status"] == "surveyed"
    assert body["site"]["viewer_has_surveyed"] is True
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

    fossils = client.get(f"/api/v1/sites/{field_site.site_id}/fossils")
    assert fossils.status_code == 200
    assert len(fossils.json()["items"]) >= 1

    site = client.get(
        f"/api/v1/sites/{field_site.site_id}",
        params={"data_source": "field"},
        headers=headers,
    )
    assert site.status_code == 200
    assert site.json()["viewer_has_surveyed"] is True
    assert site.json()["status"] == "surveyed"
