"""Always-on worker for field-site ensure jobs."""

from __future__ import annotations

import logging
import os
import socket
import time
import uuid

from sqlmodel import Session

from app.core.database import engine, run_migrations
from app.models.field_ensure_job import FieldEnsureJob
from app.services.site_service.field_ensure_queue import (
    claim_next_job,
    count_running_jobs,
    mark_job_done,
    mark_job_failed,
    recover_stale_running_jobs,
)
from app.services.site_service.field_coordinate_filter import (
    ensure_osm_coordinate_masks_on_disk,
    warm_coordinate_filter_cache,
)
from app.services.site_service.field_generate import (
    FieldSiteLazyConfig,
    ensure_field_sites_nearby,
)
from app.services.site_service.field_site_logging import log_field_event, normalize_reason

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
    reason = normalize_reason(job.reason)
    started = time.monotonic()
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
            "ensure_complete",
            service="worker",
            reason=reason,
            lat=job.lat,
            lon=job.lon,
            radius_km=job.radius_km,
            cell=job.cell_key,
            written=result.generated,
            total_in_radius=result.total_in_radius,
            skipped=result.generated == 0,
            elapsed_s=round(time.monotonic() - started, 1),
            job_id=job.id,
        )
        return True
    except Exception as exc:
        log_field_event(
            "worker_failed",
            service="worker",
            reason=reason,
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
    worker_id = _worker_id()
    log_field_event(
        "worker_start",
        service="worker",
        worker=worker_id,
        max_concurrent=MAX_CONCURRENT,
        poll_s=POLL_INTERVAL_S,
    )
    while True:
        processed = process_one_job(worker_id=worker_id)
        if not processed:
            time.sleep(POLL_INTERVAL_S)


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    print("field_ensure_worker: starting", flush=True)
    run_migrations()
    print("field_ensure_worker: migrations complete", flush=True)
    try:
        ensure_osm_coordinate_masks_on_disk()
        print("field_ensure_worker: coordinate masks ready", flush=True)
        warm_coordinate_filter_cache()
    except RuntimeError as exc:
        logging.error("field_ensure_worker: %s", exc)
        raise SystemExit(1) from exc
    run_forever()


if __name__ == "__main__":
    main()
