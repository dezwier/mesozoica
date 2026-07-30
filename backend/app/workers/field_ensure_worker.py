"""Always-on worker for field-site ensure and survey jobs."""

from __future__ import annotations

import logging
import os
import socket
import time
import uuid

from sqlmodel import Session

from app.core.database import engine, run_migrations
from app.models.field_ensure_job import FieldEnsureJob
from app.models.field_survey_job import FieldSurveyJob
from app.services.field_service.field_ensure_queue import (
    claim_next_job,
    count_running_jobs,
    mark_job_done,
    mark_job_failed,
    recover_stale_running_jobs,
)
from app.services.field_service.field_coordinate_filter import (
    ensure_osm_coordinate_masks_on_disk,
    warm_coordinate_filter_cache,
)
from app.services.field_service.field_fossil_generate import ensure_field_fossils_for_site
from app.services.field_service.field_generate import (
    FieldSiteLazyConfig,
    ensure_field_sites_nearby,
)
from app.services.field_service.field_site_logging import log_field_event, normalize_reason
from app.services.field_service.field_survey_queue import (
    claim_next_survey_job,
    count_running_survey_jobs,
    mark_survey_job_done,
    mark_survey_job_failed,
    recover_stale_running_survey_jobs,
)

POLL_INTERVAL_S = float(os.getenv("FIELD_ENSURE_POLL_INTERVAL_S", "5"))
MAX_CONCURRENT = int(os.getenv("FIELD_ENSURE_MAX_CONCURRENT", "2"))
MAX_CONCURRENT_SURVEY = int(os.getenv("FIELD_SURVEY_MAX_CONCURRENT", "2"))


def _worker_id() -> str:
    host = socket.gethostname()
    return f"{host}-{os.getpid()}-{uuid.uuid4().hex[:8]}"


def process_one_ensure_job(*, worker_id: str) -> bool:
    with Session(engine) as session:
        recover_stale_running_jobs(session)
        if count_running_jobs(session) >= MAX_CONCURRENT:
            return False
        job = claim_next_job(session, worker_id=worker_id)
        if job is None:
            return False

    config = FieldSiteLazyConfig.from_game_config(radius_km=job.radius_km)
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
                mark_job_done(
                    session,
                    refreshed,
                    generated_count=result.generated,
                    total_in_radius=result.total_in_radius,
                )
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


def process_one_survey_job(*, worker_id: str) -> bool:
    with Session(engine) as session:
        recover_stale_running_survey_jobs(session)
        if count_running_survey_jobs(session) >= MAX_CONCURRENT_SURVEY:
            return False
        job = claim_next_survey_job(session, worker_id=worker_id)
        if job is None:
            return False

    started = time.monotonic()
    try:
        with Session(engine) as session:
            result = ensure_field_fossils_for_site(session, site_id=job.site_id)
            fossil_count = result.generated
            if result.skipped:
                from app.services.field_service.field_fossil_generate import (
                    count_field_fossils_for_site,
                )

                fossil_count = count_field_fossils_for_site(session, job.site_id)
            from app.services.field_service.field_fossil_onboard import (
                grant_surface_fossils_to_site_discoverers,
            )

            grant_surface_fossils_to_site_discoverers(
                session, site_id=job.site_id
            )
        with Session(engine) as session:
            refreshed = session.get(FieldSurveyJob, job.id)
            if refreshed is not None:
                mark_survey_job_done(
                    session,
                    refreshed,
                    fossil_count=fossil_count,
                )
        log_field_event(
            "survey_complete",
            service="worker",
            site_id=job.site_id,
            written=fossil_count,
            skipped=result.skipped,
            elapsed_s=round(time.monotonic() - started, 1),
            job_id=job.id,
        )
        return True
    except Exception as exc:
        log_field_event(
            "survey_worker_failed",
            service="worker",
            site_id=job.site_id,
            worker=worker_id,
            job_id=job.id,
            error=str(exc)[:200],
        )
        with Session(engine) as session:
            refreshed = session.get(FieldSurveyJob, job.id)
            if refreshed is not None:
                mark_survey_job_failed(session, refreshed, str(exc))
        return True


def process_one_job(*, worker_id: str) -> bool:
    """Process one ensure, survey, or tool-mission tick; prefer ensure then survey."""
    if process_one_ensure_job(worker_id=worker_id):
        return True
    if process_one_survey_job(worker_id=worker_id):
        return True
    with Session(engine) as session:
        from app.services.tool_action_service import process_aerial_mission_tick

        return process_aerial_mission_tick(session)


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
