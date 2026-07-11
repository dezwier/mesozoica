"""
Single entrypoint for all scheduled jobs.

  python -m app.crons.runner
    Run every enabled job whose cron schedule matches the current minute (UTC).

  python -m app.crons.runner --job wikipedia_dinosaur_sync
    Run one job once (ignores schedule); useful for debugging.

Platform note: Railway cronSchedule must invoke this runner at least as often as the
finest granularity required by jobs in crons.yaml (e.g. hourly for weekly jobs).
Schedules in crons.yaml are evaluated in UTC with minute resolution.
"""

from __future__ import annotations

import argparse
import logging
from datetime import datetime, timezone
from typing import Any, Callable

from croniter import croniter

from app.crons.config import CronJobDef, load_cron_config
from app.services.dinosaur_name_filter import parse_dino_names
from app.crons.jobs import dinosaur_llm_enrich, pbdb_fossil_sync, wikipedia_dinosaur_sync
from app.crons.logging_config import configure_cron_logging
from app.crons.railway_guard import require_railway_database

logger = logging.getLogger(__name__)


def cron_matches_now(schedule: str, now: datetime) -> bool:
    """True if `now` (minute resolution) is a fire time for standard 5-field cron `schedule` (UTC)."""
    if now.tzinfo is not None:
        n = now.astimezone(timezone.utc).replace(second=0, microsecond=0, tzinfo=None)
    else:
        n = now.replace(second=0, microsecond=0)
    return bool(croniter.match(schedule, n))


def _run_wikipedia_dinosaur_sync(params: dict[str, Any]) -> int:
    max_pages = params.get("max_pages")
    return wikipedia_dinosaur_sync.run_sync_job(
        dry_run=bool(params.get("dry_run", False)),
        overwrite=bool(params.get("overwrite", False)),
        max_pages=int(max_pages) if max_pages is not None else None,
        category=params.get("category"),
        dinos=params.get("dinos"),
    )


def _run_dinosaur_llm_enrich(params: dict[str, Any]) -> int:
    max_records = params.get("max_records")
    return dinosaur_llm_enrich.run_enrich_job(
        dry_run=bool(params.get("dry_run", False)),
        overwrite=bool(params.get("overwrite", False)),
        max_records=int(max_records) if max_records is not None else None,
        dinos=params.get("dinos"),
    )


def _run_pbdb_fossil_sync(params: dict[str, Any]) -> int:
    return pbdb_fossil_sync.run_sync_job(
        dry_run=bool(params.get("dry_run", False)),
        dinos=params.get("dinos"),
    )


_JOB_HANDLERS: dict[str, Callable[[dict[str, Any]], int]] = {
    "wikipedia_dinosaur_sync": _run_wikipedia_dinosaur_sync,
    "dinosaur_llm_enrich": _run_dinosaur_llm_enrich,
    "pbdb_fossil_sync": _run_pbdb_fossil_sync,
}


def run_single_job(job: CronJobDef, param_overrides: dict[str, Any] | None = None) -> int:
    handler = _JOB_HANDLERS.get(job.id)
    if handler is None:
        logger.error("Unknown cron job id: %s", job.id)
        return 1
    params = dict(job.params or {})
    if param_overrides:
        params.update(param_overrides)
    logger.info("Running cron job %s", job.id)
    return handler(params)


def run_scheduled_pass(now: datetime | None = None) -> int:
    """Run all enabled jobs whose schedule matches `now` (default: UTC now)."""
    if now is None:
        now = datetime.now(timezone.utc)
    cfg = load_cron_config()
    exit_code = 0
    for job in cfg.jobs:
        if not job.enabled:
            logger.debug("Skip disabled job %s", job.id)
            continue
        if not cron_matches_now(job.schedule, now):
            logger.debug(
                "Skip job %s (schedule %s does not match %s)",
                job.id,
                job.schedule,
                now.isoformat(),
            )
            continue
        code = run_single_job(job)
        if code != 0:
            exit_code = code
    return exit_code


def main(argv: list[str] | None = None) -> int:
    configure_cron_logging()
    require_railway_database()
    parser = argparse.ArgumentParser(description="Run scheduled jobs from app/crons/crons.yaml")
    parser.add_argument(
        "--job",
        metavar="ID",
        help="Run a single job by id (ignores schedule). E.g. wikipedia_dinosaur_sync.",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Re-fetch Wikipedia records even when already up to date (wikipedia_dinosaur_sync). "
        "Re-run LLM enrichment even when llm_enriched=true (dinosaur_llm_enrich).",
    )
    parser.add_argument(
        "--dinos",
        metavar="NAME",
        nargs="+",
        help="Limit to specific dinosaurs by Wikipedia title (e.g. Tyrannosaurus). "
        "Pass multiple names or comma-separated names in one argument.",
    )
    args = parser.parse_args(argv)

    overrides: dict[str, Any] = {}
    if args.overwrite:
        overrides["overwrite"] = True
    dinos = parse_dino_names(args.dinos)
    if dinos:
        overrides["dinos"] = dinos

    if args.job:
        cfg = load_cron_config()
        job = next((j for j in cfg.jobs if j.id == args.job), None)
        if job is None:
            logger.error("No job with id %r in cron config", args.job)
            return 1
        return run_single_job(job, overrides or None)

    return run_scheduled_pass()


if __name__ == "__main__":
    raise SystemExit(main())
