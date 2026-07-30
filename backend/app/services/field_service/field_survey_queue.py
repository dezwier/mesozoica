"""Postgres-backed field survey job enqueue (lazy fossil generation per site)."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, col, func, select, text

from app.core.database import engine
from app.models.field_survey_job import FieldSurveyJob

STATUS_PENDING = "pending"
STATUS_RUNNING = "running"
STATUS_DONE = "done"
STATUS_FAILED = "failed"


def enqueue_field_survey(
    session: Session,
    *,
    site_id: int,
    user_id: int,
) -> tuple[bool, FieldSurveyJob]:
    """Enqueue or onboard a survey fossil-generation job for ``site_id``.

    Returns ``(accepted, job)``. ``accepted`` is False when the site already has
    a pending/running job (caller still gets that job for onboarding).
    """
    job = session.exec(
        select(FieldSurveyJob).where(col(FieldSurveyJob.site_id) == site_id)
    ).first()

    if job is not None:
        if job.status in (STATUS_PENDING, STATUS_RUNNING):
            return False, job

        # Fossils already generated (or prior failure) — reset only if failed;
        # done jobs stay done and are not re-enqueued by this helper.
        if job.status == STATUS_DONE:
            return False, job

        job.initiated_by_user_id = user_id
        job.status = STATUS_PENDING
        job.fossil_count = None
        job.worker_id = None
        job.error_message = None
        job.started_at = None
        job.finished_at = None
        session.add(job)
        session.commit()
        session.refresh(job)
        return True, job

    job = FieldSurveyJob(
        site_id=site_id,
        initiated_by_user_id=user_id,
        status=STATUS_PENDING,
        created_at=datetime.now(timezone.utc).replace(tzinfo=None),
    )
    session.add(job)
    try:
        session.commit()
        session.refresh(job)
    except IntegrityError:
        session.rollback()
        existing = session.exec(
            select(FieldSurveyJob).where(col(FieldSurveyJob.site_id) == site_id)
        ).first()
        if existing is None:
            raise
        return False, existing

    return True, job


def count_running_survey_jobs(session: Session) -> int:
    return int(
        session.exec(
            select(func.count())
            .select_from(FieldSurveyJob)
            .where(col(FieldSurveyJob.status) == STATUS_RUNNING)
        ).one()
    )


def recover_stale_running_survey_jobs(
    session: Session,
    *,
    stale_after: timedelta = timedelta(minutes=30),
) -> int:
    cutoff = datetime.now(timezone.utc).replace(tzinfo=None) - stale_after
    stale_jobs = session.exec(
        select(FieldSurveyJob).where(
            col(FieldSurveyJob.status) == STATUS_RUNNING,
            col(FieldSurveyJob.started_at).is_not(None),
            col(FieldSurveyJob.started_at) < cutoff,
        )
    ).all()
    for job in stale_jobs:
        job.status = STATUS_PENDING
        job.worker_id = None
        job.started_at = None
        session.add(job)
    if stale_jobs:
        session.commit()
    return len(stale_jobs)


def claim_next_survey_job(
    session: Session, *, worker_id: str
) -> FieldSurveyJob | None:
    if engine.dialect.name == "postgresql":
        row = session.exec(
            text(
                """
                SELECT id
                FROM field_survey_job
                WHERE status = :pending
                ORDER BY created_at
                FOR UPDATE SKIP LOCKED
                LIMIT 1
                """
            ).bindparams(pending=STATUS_PENDING)
        ).first()
        if row is None:
            return None
        job_id = row[0] if isinstance(row, tuple) else row.id
        job = session.get(FieldSurveyJob, job_id)
    else:
        job = session.exec(
            select(FieldSurveyJob)
            .where(col(FieldSurveyJob.status) == STATUS_PENDING)
            .order_by(col(FieldSurveyJob.created_at))
        ).first()

    if job is None:
        return None

    job.status = STATUS_RUNNING
    job.worker_id = worker_id
    job.started_at = datetime.now(timezone.utc).replace(tzinfo=None)
    job.attempts += 1
    session.add(job)
    session.commit()
    session.refresh(job)
    return job


def mark_survey_job_done(
    session: Session,
    job: FieldSurveyJob,
    *,
    fossil_count: int,
) -> None:
    job.status = STATUS_DONE
    job.finished_at = datetime.now(timezone.utc).replace(tzinfo=None)
    job.error_message = None
    job.fossil_count = fossil_count
    session.add(job)
    session.commit()


def mark_survey_job_failed(
    session: Session, job: FieldSurveyJob, error_message: str
) -> None:
    job.status = STATUS_FAILED
    job.finished_at = datetime.now(timezone.utc).replace(tzinfo=None)
    job.error_message = error_message[:2000]
    session.add(job)
    session.commit()


def get_field_survey_job(session: Session, job_id: int) -> FieldSurveyJob | None:
    return session.get(FieldSurveyJob, job_id)
