"""Orchestrate Gemini enrichment of fossil occurrence records."""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass

from sqlalchemy import case, update
from sqlmodel import Session, col, func, select

from app.core.config import settings
from app.models.dinosaur_type import DinosaurType
from app.models.data_source import DATA_SOURCE_ARCHIVE
from app.models.fossil import Fossil
from app.services.dinosaur_image_service.sync import CURATED_MEDIA_PATH
from app.services.dinosaur_name_filter import dino_name_match_clause
from app.services.enrichment_common import (
    EnrichCounters,
    EnrichSummary,
    enrich_exit_code as shared_enrich_exit_code,
)
from app.services.fossil_enrichment_service.impute import impute_llm_fields
from app.services.fossil_enrichment_service.pbdb_hints import apply_pbdb_hints
from app.services.fossil_enrichment_service.prompt import build_enrichment_prompt
from app.services.fossil_enrichment_service.validate import validate_llm_enrichment
from app.services.llm_service.client import call_gemini_api

logger = logging.getLogger("fossil_enrich")

_FOSSIL_ENRICH_MAX_OUTPUT_TOKENS = 4096

# Re-export for callers/tests that import from this module.
__all__ = [
    "EnrichCounters",
    "EnrichSummary",
    "enrich_exit_code",
    "enrich_fossils",
    "reset_llm_enriched_flags",
]


@dataclass(frozen=True)
class FossilCandidate:
    fossil: Fossil
    dinosaur: DinosaurType


def reset_llm_enriched_flags(
    session: Session,
    *,
    dinos: list[str] | None = None,
    dry_run: bool = False,
) -> int:
    """Clear llm_enriched so an interrupted overwrite run can resume without --overwrite."""
    if dry_run:
        stmt = select(func.count()).select_from(Fossil).where(
            Fossil.llm_enriched.is_(True),  # type: ignore[attr-defined]
            col(Fossil.data_source) == DATA_SOURCE_ARCHIVE,
        )
        if dinos:
            stmt = stmt.join(DinosaurType, Fossil.dinosaur_id == DinosaurType.id).where(
                dino_name_match_clause(dinos)
            )
        return int(session.exec(stmt).one())

    stmt = update(Fossil).values(llm_enriched=False).where(
        Fossil.llm_enriched.is_(True),  # type: ignore[attr-defined]
        col(Fossil.data_source) == DATA_SOURCE_ARCHIVE,
    )
    if dinos:
        dinosaur_ids = select(DinosaurType.id).where(dino_name_match_clause(dinos))  # type: ignore[arg-type]
        stmt = stmt.where(col(Fossil.dinosaur_id).in_(dinosaur_ids))
    result = session.exec(stmt)
    session.commit()
    return int(result.rowcount or 0)


def _select_candidates(
    session: Session,
    *,
    include_enriched: bool,
    max_records: int | None,
    dinos: list[str] | None = None,
) -> list[FossilCandidate]:
    stmt = select(Fossil, DinosaurType).join(
        DinosaurType, Fossil.dinosaur_id == DinosaurType.id
    ).where(col(Fossil.data_source) == DATA_SOURCE_ARCHIVE)
    if not include_enriched:
        stmt = stmt.where(Fossil.llm_enriched.is_(False))  # type: ignore[attr-defined]
    if dinos:
        stmt = stmt.where(dino_name_match_clause(dinos))
    fossils_synced_priority = case(
        (col(DinosaurType.fossils_insert_time).is_not(None), 0),
        else_=1,
    )
    custom_image_priority = case(
        (
            col(DinosaurType.main_image_url).is_not(None)
            & col(DinosaurType.main_image_url).contains(CURATED_MEDIA_PATH),
            0,
        ),
        else_=1,
    )
    stmt = stmt.order_by(
        fossils_synced_priority,
        custom_image_priority,
        DinosaurType.name,
        Fossil.id,
    )  # type: ignore[arg-type]
    if max_records is not None:
        stmt = stmt.limit(max_records)
    rows = session.exec(stmt).all()
    return [FossilCandidate(fossil=fossil, dinosaur=dinosaur) for fossil, dinosaur in rows]


def _apply_enrichment(fossil: Fossil, raw: dict) -> None:
    validated = apply_pbdb_hints(fossil, validate_llm_enrichment(raw))
    imputed = impute_llm_fields(validated)
    fossil.llm_rock_type = validated.llm_rock_type
    fossil.llm_category = validated.llm_category
    fossil.llm_subcategory = validated.llm_subcategory
    fossil.llm_preservation_quality = validated.llm_preservation_quality
    fossil.llm_completeness = validated.llm_completeness
    fossil.llm_description = validated.llm_description
    fossil.llm_imp_rock_type = imputed.llm_imp_rock_type
    fossil.llm_imp_category = imputed.llm_imp_category
    fossil.llm_imp_subcategory = imputed.llm_imp_subcategory
    fossil.llm_imp_preservation_quality = imputed.llm_imp_preservation_quality
    fossil.llm_imp_completeness = imputed.llm_imp_completeness
    fossil.llm_enriched = True


def enrich_fossils(
    session: Session,
    *,
    dry_run: bool = False,
    overwrite: bool = False,
    max_records: int | None = None,
    dinos: list[str] | None = None,
) -> EnrichSummary:
    """Enrich fossil occurrence records via Gemini API."""
    if not settings.google_gemini_api_key:
        raise RuntimeError("GOOGLE_GEMINI_API_KEY is required for fossil enrichment")

    cap = max_records if max_records is not None else settings.fossil_enrich_max_records
    delay_s = settings.fossil_enrich_request_delay_ms / 1000.0

    start = time.monotonic()
    counters = EnrichCounters()

    if overwrite and not dry_run:
        reset_count = reset_llm_enriched_flags(session, dinos=dinos)
        logger.info(
            "fossil_enrich: reset llm_enriched count=%d dinos=%s",
            reset_count,
            dinos,
        )

    candidates = _select_candidates(
        session,
        include_enriched=overwrite and dry_run,
        max_records=cap,
        dinos=dinos,
    )
    total = len(candidates)

    logger.info(
        "fossil_enrich: starting total_candidates=%d overwrite=%s dinos=%s",
        total,
        overwrite,
        dinos,
    )

    for index, candidate in enumerate(candidates, start=1):
        fossil = candidate.fossil
        dinosaur = candidate.dinosaur
        prefix = f"fossil_enrich: [{index}/{total}] {fossil.id} ({dinosaur.name})"
        try:
            system_instruction, user_prompt = build_enrichment_prompt(
                fossil, dinosaur=dinosaur
            )
            raw, _usage = call_gemini_api(
                user_prompt,
                system_instruction=system_instruction,
                response_mime_type_json=True,
                max_output_tokens=_FOSSIL_ENRICH_MAX_OUTPUT_TOKENS,
                thinking_budget=0,
                timeout_seconds=120,
                log_context=str(fossil.id),
            )

            if dry_run:
                validated = apply_pbdb_hints(fossil, validate_llm_enrichment(raw))
                impute_llm_fields(validated)
                counters.enriched += 1
                logger.info("%s action=enrich reason=dry_run", prefix)
            else:
                _apply_enrichment(fossil, raw)
                session.add(fossil)
                session.commit()
                counters.enriched += 1
                reason = "overwrite" if overwrite else "new"
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
        "fossil_enrich: finished enriched=%d skipped=%d failed=%d "
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
    return shared_enrich_exit_code(
        summary,
        failure_threshold=settings.fossil_enrich_failure_threshold,
    )
