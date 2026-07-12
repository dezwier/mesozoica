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
from app.crons.jobs import (
    dinosaur_image_generate,
    dinosaur_llm_enrich,
    fossil_image_generate,
    pbdb_fossil_sync,
    wikipedia_dinosaur_sync,
)
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


def _parse_since(raw: Any) -> datetime | None:
    if raw is None:
        return None
    if isinstance(raw, datetime):
        return raw if raw.tzinfo else raw.replace(tzinfo=timezone.utc)
    text = str(raw).strip()
    if not text:
        return None
    parsed = datetime.fromisoformat(text.replace("Z", "+00:00"))
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)


def _run_pbdb_fossil_sync(params: dict[str, Any]) -> int:
    stale_days = params.get("stale_days")
    return pbdb_fossil_sync.run_sync_job(
        dry_run=bool(params.get("dry_run", False)),
        overwrite=bool(params.get("overwrite", False)),
        dinos=params.get("dinos"),
        since=_parse_since(params.get("since")),
        stale_days=int(stale_days) if stale_days is not None else None,
    )


def _parse_max_items(raw: Any) -> int | None:
    if raw is None:
        return None
    if raw in ("", "none", "null"):
        return None
    return int(raw)


def _run_dinosaur_image_generate(params: dict[str, Any]) -> int:
    return dinosaur_image_generate.run_generate_job(
        dry_run=bool(params.get("dry_run", False)),
        max_items=_parse_max_items(params.get("max_items")),
        dinos=params.get("dinos"),
    )


def _run_fossil_image_generate(params: dict[str, Any]) -> int:
    return fossil_image_generate.run_generate_job(
        dry_run=bool(params.get("dry_run", False)),
        max_items=_parse_max_items(params.get("max_items")),
        dinos=params.get("dinos"),
    )


_JOB_HANDLERS: dict[str, Callable[[dict[str, Any]], int]] = {
    "wikipedia_dinosaur_sync": _run_wikipedia_dinosaur_sync,
    "dinosaur_llm_enrich": _run_dinosaur_llm_enrich,
    "pbdb_fossil_sync": _run_pbdb_fossil_sync,
    "dinosaur_image_generate": _run_dinosaur_image_generate,
    "fossil_image_generate": _run_fossil_image_generate,
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
        "Re-run LLM enrichment even when llm_enriched=true (dinosaur_llm_enrich). "
        "Re-fetch PBDB fossil occurrences even when already synced (pbdb_fossil_sync).",
    )
    parser.add_argument(
        "--category",
        metavar="NAME",
        help="Limit Wikipedia dinosaur sync to one category "
        '(e.g. "Category:Feathered dinosaurs").',
    )
    parser.add_argument(
        "--dinos",
        metavar="NAME",
        nargs="+",
        help="Limit to specific dinosaurs by Wikipedia title (e.g. Tyrannosaurus). "
        "Pass multiple names or comma-separated names in one argument.",
    )
    parser.add_argument(
        "--stale-days",
        metavar="N",
        type=int,
        help="Only sync dinosaurs whose fossils_insert_time is null or older than N days "
        "(pbdb_fossil_sync; ignored with --overwrite).",
    )
    parser.add_argument(
        "--since",
        metavar="ISO8601",
        help="Only sync dinosaurs whose fossils_insert_time is null or before this UTC "
        "timestamp (pbdb_fossil_sync; ignored with --overwrite).",
    )
    parser.add_argument(
        "--max-items",
        metavar="N",
        type=int,
        help="Maximum successful image generations per run (dinosaur_image_generate, "
        "fossil_image_generate).",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview image generation candidates without calling Imagen or writing files.",
    )
    args = parser.parse_args(argv)

    overrides: dict[str, Any] = {}
    if args.overwrite:
        overrides["overwrite"] = True
    if args.category:
        overrides["category"] = args.category.strip()
    dinos = parse_dino_names(args.dinos)
    if dinos:
        overrides["dinos"] = dinos
    if args.stale_days is not None:
        overrides["stale_days"] = args.stale_days
    if args.since is not None:
        overrides["since"] = args.since
    if args.max_items is not None:
        overrides["max_items"] = args.max_items
    if args.dry_run:
        overrides["dry_run"] = True

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
