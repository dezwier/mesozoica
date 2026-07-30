"""Postgres-backed field-site ensure job enqueue."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, col, func, select, text

from app.core.database import engine
from app.models.field_ensure_job import FieldEnsureJob
from app.services.field_service.field_generate import FieldSiteLazyConfig
from app.services.field_service.field_site_logging import log_field_event, normalize_reason

STATUS_PENDING = "pending"
STATUS_RUNNING = "running"
STATUS_DONE = "done"
STATUS_FAILED = "failed"


def cell_key(lat: float, lon: float, radius_km: float) -> str:
    return f"{round(lat, 2)}:{round(lon, 2)}:{radius_km}"


def enqueue_field_site_ensure(
    session: Session,
    *,
    lat: float,
    lon: float,
    config: FieldSiteLazyConfig | None = None,
    reason: str | None = None,
) -> tuple[bool, int | None]:
    """Enqueue a worker job for density check and generation.

    Does not count sites in radius — the worker re-counts before generating.
    Returns ``(accepted, job_id)``. ``accepted`` is False when the cell already
    has a pending/running job; ``job_id`` is still the existing job when present.
    """
    cfg = config or FieldSiteLazyConfig.from_game_config()
    cfg.validate()
    trigger = normalize_reason(reason)
    key = cell_key(lat, lon, cfg.radius_km)

    job = session.exec(
        select(FieldEnsureJob).where(col(FieldEnsureJob.cell_key) == key)
    ).first()

    if job is not None:
        if job.status in (STATUS_PENDING, STATUS_RUNNING):
            return False, job.id

        job.lat = lat
        job.lon = lon
        job.radius_km = cfg.radius_km
        job.missing_count = 0
        job.generated_count = None
        job.total_in_radius = None
        job.reason = trigger
        job.status = STATUS_PENDING
        job.worker_id = None
        job.error_message = None
        job.started_at = None
        job.finished_at = None
        session.add(job)
        session.commit()
        session.refresh(job)
        return True, job.id

    job = FieldEnsureJob(
        cell_key=key,
        lat=lat,
        lon=lon,
        radius_km=cfg.radius_km,
        missing_count=0,
        reason=trigger,
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
            select(FieldEnsureJob).where(col(FieldEnsureJob.cell_key) == key)
        ).first()
        return False, existing.id if existing is not None else None

    return True, job.id


def schedule_field_site_ensure(
    *,
    lat: float,
    lon: float,
    config: FieldSiteLazyConfig | None = None,
    reason: str | None = None,
) -> tuple[bool, int | None]:
    """API helper: open a session and enqueue a job."""
    with Session(engine) as session:
        return enqueue_field_site_ensure(
            session,
            lat=lat,
            lon=lon,
            config=config,
            reason=reason,
        )


def count_running_jobs(session: Session) -> int:
    return int(
        session.exec(
            select(func.count())
            .select_from(FieldEnsureJob)
            .where(col(FieldEnsureJob.status) == STATUS_RUNNING)
        ).one()
    )


def recover_stale_running_jobs(
    session: Session,
    *,
    stale_after: timedelta = timedelta(minutes=30),
) -> int:
    cutoff = datetime.now(timezone.utc).replace(tzinfo=None) - stale_after
    stale_jobs = session.exec(
        select(FieldEnsureJob).where(
            col(FieldEnsureJob.status) == STATUS_RUNNING,
            col(FieldEnsureJob.started_at).is_not(None),
            col(FieldEnsureJob.started_at) < cutoff,
        )
    ).all()
    for job in stale_jobs:
        job.status = STATUS_PENDING
        job.worker_id = None
        job.started_at = None
        session.add(job)
    if stale_jobs:
        session.commit()
        log_field_event("ensure_stale_recovered", recovered=len(stale_jobs))
    return len(stale_jobs)


def claim_next_job(session: Session, *, worker_id: str) -> FieldEnsureJob | None:
    if engine.dialect.name == "postgresql":
        row = session.exec(
            text(
                """
                SELECT id
                FROM field_ensure_job
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
        job = session.get(FieldEnsureJob, job_id)
    else:
        job = session.exec(
            select(FieldEnsureJob)
            .where(col(FieldEnsureJob.status) == STATUS_PENDING)
            .order_by(col(FieldEnsureJob.created_at))
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


def mark_job_done(
    session: Session,
    job: FieldEnsureJob,
    *,
    generated_count: int | None = None,
    total_in_radius: int | None = None,
) -> None:
    job.status = STATUS_DONE
    job.finished_at = datetime.now(timezone.utc).replace(tzinfo=None)
    job.error_message = None
    if generated_count is not None:
        job.generated_count = generated_count
    if total_in_radius is not None:
        job.total_in_radius = total_in_radius
    session.add(job)
    session.commit()


def get_field_ensure_job(session: Session, job_id: int) -> FieldEnsureJob | None:
    return session.get(FieldEnsureJob, job_id)


def mark_job_failed(session: Session, job: FieldEnsureJob, error_message: str) -> None:
    job.status = STATUS_FAILED
    job.finished_at = datetime.now(timezone.utc).replace(tzinfo=None)
    job.error_message = error_message[:2000]
    session.add(job)
    session.commit()
