"""Postgres-backed field-site ensure job enqueue."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, col, func, select, text

from app.core.database import engine
from app.models.data_source import DATA_SOURCE_FIELD
from app.models.field_ensure_job import FieldEnsureJob
from app.services.site_service.field_generate import FieldSiteLazyConfig
from app.services.site_service.field_site_logging import log_field_event, normalize_reason
from app.services.site_service.nearby import count_sites_in_radius

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
) -> tuple[int, int, bool]:
    """Count local density and enqueue a worker job when under-filled.

    Returns ``(existing_in_radius, missing, accepted)``.
    """
    cfg = config or FieldSiteLazyConfig()
    cfg.validate()
    trigger = normalize_reason(reason)

    existing = count_sites_in_radius(
        session,
        lat=lat,
        lon=lon,
        radius_km=cfg.radius_km,
        data_source=DATA_SOURCE_FIELD,
    )
    missing = max(0, cfg.min_sites_in_radius - existing)
    key = cell_key(lat, lon, cfg.radius_km)

    if missing == 0:
        log_field_event(
            "ensure_check",
            lat=lat,
            lon=lon,
            radius_km=cfg.radius_km,
            cell=key,
            reason=trigger,
            existing=existing,
            missing=0,
            enqueued=False,
            written=0,
        )
        return existing, 0, True

    job = session.exec(
        select(FieldEnsureJob).where(col(FieldEnsureJob.cell_key) == key)
    ).first()

    if job is not None:
        if job.status in (STATUS_PENDING, STATUS_RUNNING):
            log_field_event(
                "ensure_check",
                lat=lat,
                lon=lon,
                radius_km=cfg.radius_km,
                cell=key,
                reason=trigger,
                existing=existing,
                missing=missing,
                enqueued=False,
                written=0,
                skip_reason="job_active",
            )
            return existing, missing, False

        job.lat = lat
        job.lon = lon
        job.radius_km = cfg.radius_km
        job.missing_count = missing
        job.reason = trigger
        job.status = STATUS_PENDING
        job.worker_id = None
        job.error_message = None
        job.started_at = None
        job.finished_at = None
        session.add(job)
        session.commit()
        log_field_event(
            "ensure_check",
            lat=lat,
            lon=lon,
            radius_km=cfg.radius_km,
            cell=key,
            reason=trigger,
            existing=existing,
            missing=missing,
            enqueued=True,
            written=0,
        )
        return existing, missing, True

    job = FieldEnsureJob(
        cell_key=key,
        lat=lat,
        lon=lon,
        radius_km=cfg.radius_km,
        missing_count=missing,
        reason=trigger,
        status=STATUS_PENDING,
        created_at=datetime.now(timezone.utc).replace(tzinfo=None),
    )
    session.add(job)
    try:
        session.commit()
    except IntegrityError:
        session.rollback()
        log_field_event(
            "ensure_check",
            lat=lat,
            lon=lon,
            radius_km=cfg.radius_km,
            cell=key,
            reason=trigger,
            existing=existing,
            missing=missing,
            enqueued=False,
            written=0,
            skip_reason="duplicate_enqueue",
        )
        return existing, missing, False

    log_field_event(
        "ensure_check",
        lat=lat,
        lon=lon,
        radius_km=cfg.radius_km,
        cell=key,
        reason=trigger,
        existing=existing,
        missing=missing,
        enqueued=True,
        written=0,
    )
    return existing, missing, True


def schedule_field_site_ensure(
    *,
    lat: float,
    lon: float,
    config: FieldSiteLazyConfig | None = None,
    reason: str | None = None,
) -> tuple[int, int, bool]:
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
    log_field_event(
        "ensure_claimed",
        lat=job.lat,
        lon=job.lon,
        radius_km=job.radius_km,
        cell=job.cell_key,
        reason=normalize_reason(job.reason),
        missing=job.missing_count,
        worker=worker_id,
        job_id=job.id,
    )
    return job


def mark_job_done(session: Session, job: FieldEnsureJob) -> None:
    job.status = STATUS_DONE
    job.finished_at = datetime.now(timezone.utc).replace(tzinfo=None)
    job.error_message = None
    session.add(job)
    session.commit()


def mark_job_failed(session: Session, job: FieldEnsureJob, error_message: str) -> None:
    job.status = STATUS_FAILED
    job.finished_at = datetime.now(timezone.utc).replace(tzinfo=None)
    job.error_message = error_message[:2000]
    session.add(job)
    session.commit()
