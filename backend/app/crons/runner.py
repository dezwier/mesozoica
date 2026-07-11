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
from app.crons.jobs import wikipedia_dinosaur_sync

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
        max_pages=int(max_pages) if max_pages is not None else None,
        category=params.get("category"),
    )


_JOB_HANDLERS: dict[str, Callable[[dict[str, Any]], int]] = {
    "wikipedia_dinosaur_sync": _run_wikipedia_dinosaur_sync,
}


def run_single_job(job: CronJobDef) -> int:
    handler = _JOB_HANDLERS.get(job.id)
    if handler is None:
        logger.error("Unknown cron job id: %s", job.id)
        return 1
    logger.info("Running cron job %s", job.id)
    return handler(job.params or {})


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
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    parser = argparse.ArgumentParser(description="Run scheduled jobs from app/crons/crons.yaml")
    parser.add_argument(
        "--job",
        metavar="ID",
        help="Run a single job by id (ignores schedule). E.g. wikipedia_dinosaur_sync.",
    )
    args = parser.parse_args(argv)

    if args.job:
        cfg = load_cron_config()
        job = next((j for j in cfg.jobs if j.id == args.job), None)
        if job is None:
            logger.error("No job with id %r in cron config", args.job)
            return 1
        return run_single_job(job)

    return run_scheduled_pass()


if __name__ == "__main__":
    raise SystemExit(main())
