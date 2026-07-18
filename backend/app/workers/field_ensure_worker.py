"""Always-on worker for field-site ensure jobs."""

from __future__ import annotations

import logging
import os
import socket
import time
import uuid

from sqlmodel import Session

from app.core.database import engine
from app.models.field_ensure_job import FieldEnsureJob
from app.services.site_service.field_ensure_queue import (
    claim_next_job,
    count_running_jobs,
    mark_job_done,
    mark_job_failed,
    recover_stale_running_jobs,
)
from app.services.site_service.field_generate import (
    FieldSiteLazyConfig,
    ensure_field_sites_nearby,
)
from app.services.site_service.field_site_logging import log_field_event

POLL_INTERVAL_S = float(os.getenv("FIELD_ENSURE_POLL_INTERVAL_S", "5"))
MAX_CONCURRENT = int(os.getenv("FIELD_ENSURE_MAX_CONCURRENT", "2"))


def _worker_id() -> str:
    host = socket.gethostname()
    return f"{host}-{os.getpid()}-{uuid.uuid4().hex[:8]}"


def process_one_job(*, worker_id: str) -> bool:
    with Session(engine) as session:
        recover_stale_running_jobs(session)
        if count_running_jobs(session) >= MAX_CONCURRENT:
            return False
        job = claim_next_job(session, worker_id=worker_id)
        if job is None:
            return False

    config = FieldSiteLazyConfig(radius_km=job.radius_km)
    try:
        with Session(engine) as session:
            result = ensure_field_sites_nearby(
                session,
                lat=job.lat,
                lon=job.lon,
                config=config,
            )
        with Session(engine) as session:
            refreshed = session.get(FieldEnsureJob, job.id)
            if refreshed is not None:
                mark_job_done(session, refreshed)
        log_field_event(
            "worker_done",
            lat=job.lat,
            lon=job.lon,
            radius_km=job.radius_km,
            cell=job.cell_key,
            generated=result.generated,
            total_in_radius=result.total_in_radius,
            worker=worker_id,
            job_id=job.id,
        )
        return True
    except Exception as exc:
        log_field_event(
            "worker_failed",
            lat=job.lat,
            lon=job.lon,
            radius_km=job.radius_km,
            cell=job.cell_key,
            worker=worker_id,
            job_id=job.id,
            error=str(exc)[:200],
        )
        with Session(engine) as session:
            refreshed = session.get(FieldEnsureJob, job.id)
            if refreshed is not None:
                mark_job_failed(session, refreshed, str(exc))
        return True


def run_forever() -> None:
    logging.basicConfig(level=logging.INFO)
    worker_id = _worker_id()
    log_field_event(
        "worker_start",
        worker=worker_id,
        max_concurrent=MAX_CONCURRENT,
        poll_s=POLL_INTERVAL_S,
    )
    while True:
        processed = process_one_job(worker_id=worker_id)
        if not processed:
            time.sleep(POLL_INTERVAL_S)


def main() -> None:
    run_forever()


if __name__ == "__main__":
    main()
