"""Orchestrate Gemini enrichment of dinosaur records."""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field

from sqlmodel import Session, select

from app.core.config import settings
from app.models.dinosaur import Dinosaur
from app.services.dinosaur_enrichment_service.prompt import build_enrichment_prompt
from app.services.dinosaur_enrichment_service.validate import validate_llm_enrichment
from app.services.llm_service.client import call_gemini_api

logger = logging.getLogger("dinosaur_enrich")


@dataclass
class EnrichCounters:
    enriched: int = 0
    skipped: int = 0
    failed: int = 0


@dataclass
class EnrichSummary:
    total_candidates: int
    counters: EnrichCounters = field(default_factory=EnrichCounters)
    dry_run: bool = False
    overwrite: bool = False
    elapsed_s: float = 0.0

    @property
    def failure_rate(self) -> float:
        attempted = self.counters.enriched + self.counters.failed
        if attempted == 0:
            return 0.0
        return self.counters.failed / attempted


def _select_candidates(
    session: Session,
    *,
    overwrite: bool,
    max_records: int | None,
) -> list[Dinosaur]:
    stmt = select(Dinosaur).where(Dinosaur.article.is_not(None))  # type: ignore[union-attr]
    if not overwrite:
        stmt = stmt.where(Dinosaur.llm_enriched.is_(False))  # type: ignore[attr-defined]
    stmt = stmt.order_by(Dinosaur.id)  # type: ignore[arg-type]
    if max_records is not None:
        stmt = stmt.limit(max_records)
    return list(session.exec(stmt).all())


def _apply_enrichment(dinosaur: Dinosaur, raw: dict) -> None:
    validated = validate_llm_enrichment(raw)
    dinosaur.length = validated.length
    dinosaur.mass = validated.mass
    dinosaur.location = validated.location
    dinosaur.diet_type = validated.diet_type
    dinosaur.short_description = validated.short_description
    dinosaur.llm_enriched = True


def enrich_dinosaurs(
    session: Session,
    *,
    dry_run: bool = False,
    overwrite: bool = False,
    max_records: int | None = None,
) -> EnrichSummary:
    """Enrich dinosaur records via Gemini API."""
    if not settings.google_gemini_api_key:
        raise RuntimeError("GOOGLE_GEMINI_API_KEY is required for dinosaur enrichment")

    cap = max_records if max_records is not None else settings.dinosaur_enrich_max_records
    delay_s = settings.dinosaur_enrich_request_delay_ms / 1000.0

    start = time.monotonic()
    counters = EnrichCounters()
    candidates = _select_candidates(session, overwrite=overwrite, max_records=cap)
    total = len(candidates)

    logger.info(
        "dinosaur_enrich: starting total_candidates=%d overwrite=%s",
        total,
        overwrite,
    )

    for index, dinosaur in enumerate(candidates, start=1):
        prefix = f"dinosaur_enrich: [{index}/{total}] {dinosaur.name}"
        try:
            if dinosaur.llm_enriched and not overwrite:
                counters.skipped += 1
                logger.info("%s action=skip reason=already_enriched", prefix)
                continue

            if not dinosaur.article:
                counters.skipped += 1
                logger.info("%s action=skip reason=no_article", prefix)
                continue

            system_instruction, user_prompt = build_enrichment_prompt(dinosaur)
            raw, _usage = call_gemini_api(
                user_prompt,
                system_instruction=system_instruction,
                response_mime_type_json=True,
                max_output_tokens=2048,
                timeout_seconds=120,
                log_context=dinosaur.name,
            )

            if dry_run:
                validate_llm_enrichment(raw)
                counters.enriched += 1
                logger.info("%s action=enrich reason=dry_run", prefix)
            else:
                was_enriched = dinosaur.llm_enriched
                _apply_enrichment(dinosaur, raw)
                session.add(dinosaur)
                session.commit()
                counters.enriched += 1
                reason = "overwrite" if was_enriched else "new"
                logger.info("%s action=enrich reason=%s", prefix, reason)

        except Exception as exc:
            counters.failed += 1
            logger.error("%s action=failed error=%s", prefix, exc)
            session.rollback()

        if index < total and delay_s > 0:
            time.sleep(delay_s)

    elapsed = time.monotonic() - start
    summary = EnrichSummary(
        total_candidates=total,
        counters=counters,
        dry_run=dry_run,
        overwrite=overwrite,
        elapsed_s=elapsed,
    )
    logger.info(
        "dinosaur_enrich: finished enriched=%d skipped=%d failed=%d "
        "overwrite=%s dry_run=%s elapsed_s=%.1f",
        counters.enriched,
        counters.skipped,
        counters.failed,
        overwrite,
        dry_run,
        elapsed,
    )
    return summary


def enrich_exit_code(summary: EnrichSummary) -> int:
    """Return non-zero if failure rate exceeds configured threshold."""
    threshold = settings.dinosaur_enrich_failure_threshold
    if summary.counters.failed == 0:
        return 0
    if summary.failure_rate > threshold:
        return 1
    return 0
