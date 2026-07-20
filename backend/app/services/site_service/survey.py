"""Survey a field site: record surveyor role and lazily generate fossils."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone

from sqlmodel import Session, col, select

from app.core.exceptions import NotFoundError, ValidationError
from app.models.data_source import DATA_SOURCE_FIELD
from app.models.field_survey_job import FieldSurveyJob
from app.models.site import Site
from app.models.user_site import USER_SITE_ROLE_SURVEYOR, UserSite
from app.services.site_service.field_fossil_generate import count_field_fossils_for_site
from app.services.site_service.field_survey_queue import (
    STATUS_DONE,
    STATUS_PENDING,
    enqueue_field_survey,
    get_field_survey_job,
)
from app.services.site_service.list import get_site_by_id


@dataclass(frozen=True)
class SurveySiteResult:
    site: SiteRow
    job_id: int | None
    job_status: str
    onboarded: bool
    generated: bool
    """True when fossils already existed (no generation needed)."""
    fossils_ready: bool


def user_has_surveyed(session: Session, *, user_id: int, site_id: int) -> bool:
    row = session.exec(
        select(UserSite).where(
            col(UserSite.user_id) == user_id,
            col(UserSite.site_id) == site_id,
            col(UserSite.role) == USER_SITE_ROLE_SURVEYOR,
        )
    ).first()
    return row is not None


def survey_site(
    session: Session,
    *,
    site_id: int,
    user_id: int,
) -> SurveySiteResult:
    """Record surveyor for ``user_id`` and ensure field fossils (lazy, once)."""
    site = session.get(Site, site_id)
    if site is None or site.data_source != DATA_SOURCE_FIELD:
        raise NotFoundError(f"Field site {site_id} not found")

    period = (site.period or "").strip()
    rock_type = (site.rock_type or "").strip()
    if not period or not rock_type:
        raise ValidationError(
            "Site must have period and rock_type before it can be surveyed"
        )

    _upsert_surveyor(session, user_id=user_id, site_id=site_id)

    fossil_count = count_field_fossils_for_site(session, site_id)
    if fossil_count > 0:
        existing_job = session.exec(
            select(FieldSurveyJob).where(col(FieldSurveyJob.site_id) == site_id)
        ).first()
        site_row = get_site_by_id(
            session,
            site_id,
            data_source=DATA_SOURCE_FIELD,
            viewer_user_id=user_id,
        )
        return SurveySiteResult(
            site=site_row,
            job_id=existing_job.id if existing_job is not None else None,
            job_status=STATUS_DONE if existing_job is None else existing_job.status,
            onboarded=True,
            generated=False,
            fossils_ready=True,
        )

    accepted, job = enqueue_field_survey(
        session, site_id=site_id, user_id=user_id
    )
    # If a prior done job exists but fossils were deleted, re-enqueue failed path
    # already handled in queue; done-without-fossils is rare — force pending.
    if job.status == STATUS_DONE and fossil_count == 0:
        job.status = STATUS_PENDING
        job.initiated_by_user_id = user_id
        job.fossil_count = None
        job.worker_id = None
        job.error_message = None
        job.started_at = None
        job.finished_at = None
        session.add(job)
        session.commit()
        session.refresh(job)
        accepted = True

    site_row = get_site_by_id(
        session,
        site_id,
        data_source=DATA_SOURCE_FIELD,
        viewer_user_id=user_id,
    )

    return SurveySiteResult(
        site=site_row,
        job_id=job.id,
        job_status=job.status,
        onboarded=not accepted,
        generated=accepted and job.status == STATUS_PENDING,
        fossils_ready=job.status == STATUS_DONE,
    )


def _upsert_surveyor(
    session: Session, *, user_id: int, site_id: int
) -> UserSite:
    now = datetime.now(timezone.utc)
    existing = session.exec(
        select(UserSite).where(
            col(UserSite.user_id) == user_id,
            col(UserSite.site_id) == site_id,
            col(UserSite.role) == USER_SITE_ROLE_SURVEYOR,
        )
    ).first()
    if existing is None:
        row = UserSite(
            user_id=user_id,
            site_id=site_id,
            role=USER_SITE_ROLE_SURVEYOR,
            timestamp=now,
        )
        session.add(row)
        session.commit()
        session.refresh(row)
        return row

    existing.timestamp = now
    session.add(existing)
    session.commit()
    session.refresh(existing)
    return existing


def get_survey_job(session: Session, job_id: int) -> FieldSurveyJob | None:
    return get_field_survey_job(session, job_id)


__all__ = [
    "SurveySiteResult",
    "STATUS_DONE",
    "STATUS_PENDING",
    "get_survey_job",
    "survey_site",
    "user_has_surveyed",
]
