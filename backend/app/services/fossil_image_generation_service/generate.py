"""Batch-generate fossil card images via Gemini Imagen."""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field

from pathlib import Path

from sqlmodel import Session, col, select

from app.core.config import settings
from app.models.dinosaur_type import DinosaurType
from app.models.data_source import DATA_SOURCE_ARCHIVE
from app.models.fossil import Fossil
from app.services.curated_image_service.versions import (
    migrate_flat_images_to_v1,
    scan_versioned_image_files,
)
from app.services.dinosaur_image_service.sync import resolve_local_source_dir_for_sync
from app.services.dinosaur_name_filter import dino_name_match_clause
from app.services.fossil_image_service.sync import resolve_local_source_dir_for_sync as resolve_fossil_output_dir
from app.services.image_generation_service.client import (
    IMAGEN_ULTRA_COST_USD_PER_IMAGE,
    ImageGenerationError,
    generate_image_with_gemini,
    short_generation_error,
)
from app.services.image_generation_service.fossil_json import fossil_to_image_prompt_dict
from app.services.image_generation_service.local_files import (
    has_local_image,
    output_png_path,
    scan_existing_stems,
)
from app.services.image_generation_service.postprocess import save_processed_png
from app.services.image_generation_service.prompting import (
    build_fossil_image_prompt,
    dinosaur_image_prompt_template,
)

logger = logging.getLogger("fossil_image_generate")

GENERATION_ATTEMPTS = 3
GENERATION_RETRY_BACKOFF_SECONDS = 1.0


def _scan_dinosaur_image_stems(dinosaur_dir: Path) -> set[str]:
    """Lowercased stems across version folders (or flat fallback)."""
    versioned = scan_versioned_image_files(dinosaur_dir)
    if versioned:
        return {Path(item.filename).stem.lower() for item in versioned}
    return scan_existing_stems(dinosaur_dir, case_insensitive=True)


@dataclass
class GenerateCounters:
    generated: int = 0
    skipped: int = 0
    failed: int = 0


@dataclass
class GenerateSummary:
    total_candidates: int
    skipped_existing: int
    counters: GenerateCounters = field(default_factory=GenerateCounters)
    dry_run: bool = False
    elapsed_s: float = 0.0
    cost_usd: float = 0.0
    output_dir: str = ""


@dataclass(frozen=True)
class FossilCandidate:
    fossil: Fossil
    dinosaur_name: str
    dinosaur_has_image: bool


def _select_candidates(
    session: Session,
    *,
    output_dir,
    existing_stems: set[str],
    dinosaur_image_stems: set[str],
    dinos: list[str] | None = None,
) -> tuple[list[FossilCandidate], int]:
    stmt = (
        select(Fossil, DinosaurType)
        .join(DinosaurType, Fossil.dinosaur_id == DinosaurType.id)
        .where(
            Fossil.llm_enriched.is_(True),  # type: ignore[attr-defined]
            col(Fossil.data_source) == DATA_SOURCE_ARCHIVE,
        )
    )
    if dinos:
        stmt = stmt.where(dino_name_match_clause(dinos))

    rows = session.exec(stmt).all()
    skipped_existing = 0
    candidates: list[FossilCandidate] = []
    for fossil, dinosaur in rows:
        stem = str(fossil.id)
        if has_local_image(output_dir, stem, existing_stems=existing_stems):
            skipped_existing += 1
            continue
        dino_has_image = dinosaur.name.lower() in dinosaur_image_stems
        candidates.append(
            FossilCandidate(
                fossil=fossil,
                dinosaur_name=dinosaur.name,
                dinosaur_has_image=dino_has_image,
            )
        )

    candidates.sort(
        key=lambda item: (
            0 if item.dinosaur_has_image else 1,
            item.dinosaur_name.lower(),
            item.fossil.id,
        )
    )
    return candidates, skipped_existing


def generate_fossil_images(
    session: Session,
    *,
    dry_run: bool = False,
    max_items: int | None = None,
    dinos: list[str] | None = None,
) -> GenerateSummary:
    """Generate missing fossil card images to the local repo folder."""
    if not settings.google_gemini_api_key.strip():
        raise RuntimeError("GOOGLE_GEMINI_API_KEY is required for fossil image generation")

    output_dir = resolve_fossil_output_dir()
    dinosaur_dir = resolve_local_source_dir_for_sync()
    migrate_flat_images_to_v1(
        dinosaur_dir,
        default_prompt=dinosaur_image_prompt_template(),
    )
    existing_stems = scan_existing_stems(output_dir, case_insensitive=False)
    dinosaur_image_stems = _scan_dinosaur_image_stems(dinosaur_dir)
    start = time.monotonic()
    counters = GenerateCounters()
    cost_usd = 0.0

    candidates, skipped_existing = _select_candidates(
        session,
        output_dir=output_dir,
        existing_stems=existing_stems,
        dinosaur_image_stems=dinosaur_image_stems,
        dinos=dinos,
    )

    _log_header(
        output_dir=output_dir,
        candidates=len(candidates),
        skipped_existing=skipped_existing,
        max_items=max_items,
        dry_run=dry_run,
    )

    for candidate in candidates:
        if max_items is not None and counters.generated >= max_items:
            break

        fossil = candidate.fossil
        stem = str(fossil.id)
        label = (
            f'fossil {stem} dino="{candidate.dinosaur_name}" '
            f'dino_image={"yes" if candidate.dinosaur_has_image else "no"}'
        )

        if has_local_image(output_dir, stem, existing_stems=existing_stems):
            counters.skipped += 1
            logger.info('%s · SKIP · image exists', label)
            continue

        fossil_data = fossil_to_image_prompt_dict(fossil)
        prompt = build_fossil_image_prompt(
            fossil_data,
            dinosaur_name=candidate.dinosaur_name,
        )
        output_path = output_png_path(output_dir, stem)

        if dry_run:
            counters.generated += 1
            logger.info(
                '%s · DRY-RUN · would write %s (prompt_len=%d)',
                label,
                output_path.name,
                len(prompt),
            )
            continue

        generated = False
        last_error = "unknown error"
        for attempt in range(1, GENERATION_ATTEMPTS + 1):
            try:
                image_bytes, usage = generate_image_with_gemini(prompt)
                save_processed_png(image_bytes, output_path)
                cost_usd += float(usage.get("cost_usd", IMAGEN_ULTRA_COST_USD_PER_IMAGE))
                existing_stems.add(stem)
                counters.generated += 1
                generated = True
                logger.info('%s · OK -> %s', label, output_path.name)
                break
            except FileExistsError:
                counters.skipped += 1
                existing_stems.add(stem)
                logger.info('%s · SKIP · image exists', label)
                generated = True
                break
            except ImageGenerationError as exc:
                last_error = str(exc)
                if attempt < GENERATION_ATTEMPTS:
                    time.sleep(GENERATION_RETRY_BACKOFF_SECONDS * attempt)
            except Exception as exc:
                last_error = str(exc)
                if attempt < GENERATION_ATTEMPTS:
                    time.sleep(GENERATION_RETRY_BACKOFF_SECONDS * attempt)

        if not generated and not dry_run:
            counters.failed += 1
            logger.error('%s · FAIL · %s', label, short_generation_error(last_error))

    elapsed = time.monotonic() - start
    summary = GenerateSummary(
        total_candidates=len(candidates),
        skipped_existing=skipped_existing,
        counters=counters,
        dry_run=dry_run,
        elapsed_s=elapsed,
        cost_usd=cost_usd,
        output_dir=str(output_dir),
    )
    _log_summary(summary)
    return summary


def generate_exit_code(summary: GenerateSummary) -> int:
    if summary.counters.failed == 0:
        return 0
    attempted = summary.counters.generated + summary.counters.failed
    if attempted == 0:
        return 0
    return 1 if summary.counters.failed / attempted > 0.10 else 0


def _log_header(
    *,
    output_dir,
    candidates: int,
    skipped_existing: int,
    max_items: int | None,
    dry_run: bool,
) -> None:
    logger.info("=== fossil_image_generate ===")
    logger.info("output_dir: %s", output_dir)
    logger.info("model: %s", settings.gemini_image_model)
    logger.info(
        "candidates: %d (skipped_existing: %d)",
        candidates,
        skipped_existing,
    )
    logger.info(
        "max_items: %s  dry_run: %s",
        max_items if max_items is not None else "none",
        dry_run,
    )


def _log_summary(summary: GenerateSummary) -> None:
    logger.info("--- summary ---")
    logger.info(
        "generated: %d  skipped: %d  failed: %d  elapsed: %.1fs  cost: $%.2f",
        summary.counters.generated,
        summary.counters.skipped,
        summary.counters.failed,
        summary.elapsed_s,
        summary.cost_usd,
    )
