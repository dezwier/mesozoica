"""Batch-generate dinosaur card images via Gemini Imagen."""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field

from sqlalchemy import func
from sqlmodel import Session, col, select

from app.core.config import settings
from app.models.dinosaur_type import DinosaurType
from app.models.fossil import Fossil
from app.services.curated_image_service.versions import (
    ensure_version_meta,
    migrate_flat_images_to_v1,
    resolve_generation_version,
    version_dir,
)
from app.services.dinosaur_image_service.sync import resolve_local_source_dir_for_sync
from app.services.dinosaur_name_filter import dino_name_match_clause
from app.services.image_generation_service.article_text import extract_article_text
from app.services.image_generation_service.client import (
    IMAGEN_ULTRA_COST_USD_PER_IMAGE,
    ImageGenerationError,
    generate_image_with_gemini,
    short_generation_error,
)
from app.services.image_generation_service.local_files import (
    has_local_image,
    output_png_path,
    scan_existing_stems,
)
from app.services.image_generation_service.postprocess import save_processed_png
from app.services.image_generation_service.prompting import (
    build_dinosaur_image_prompt,
    dinosaur_image_prompt_template,
)
logger = logging.getLogger("dinosaur_image_generate")

GENERATION_ATTEMPTS = 3
GENERATION_RETRY_BACKOFF_SECONDS = 1.0


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
    version: str = "v1"

@dataclass(frozen=True)
class DinosaurCandidate:
    dinosaur: DinosaurType
    fossil_count: int


def _select_candidates(
    session: Session,
    *,
    output_dir,
    existing_stems: set[str],
    dinos: list[str] | None = None,
) -> tuple[list[DinosaurCandidate], int]:
    stmt = (
        select(DinosaurType, func.count(Fossil.id).label("fossil_count"))
        .outerjoin(Fossil, Fossil.dinosaur_id == DinosaurType.id)
        .where(col(DinosaurType.article).is_not(None))
        .where(col(DinosaurType.article) != "")
        .group_by(DinosaurType.id)
        .order_by(func.count(Fossil.id).desc(), DinosaurType.name)
    )
    if dinos:
        stmt = stmt.where(dino_name_match_clause(dinos))

    rows = session.exec(stmt).all()
    skipped_existing = 0
    candidates: list[DinosaurCandidate] = []
    for dinosaur, fossil_count in rows:
        if has_local_image(
            output_dir,
            dinosaur.name,
            existing_stems=existing_stems,
            case_insensitive=True,
        ):
            skipped_existing += 1
            continue
        candidates.append(
            DinosaurCandidate(dinosaur=dinosaur, fossil_count=int(fossil_count or 0))
        )
    return candidates, skipped_existing


def generate_dinosaur_images(
    session: Session,
    *,
    dry_run: bool = False,
    max_items: int | None = None,
    dinos: list[str] | None = None,
    version: str | int | None = None,
) -> GenerateSummary:
    """Generate missing dinosaur card images into ``images/dinosaurs/vN/``.

    When ``version`` is omitted, auto-increments to the next version folder.
    """
    if not settings.google_gemini_api_key.strip():
        raise RuntimeError("GOOGLE_GEMINI_API_KEY is required for dinosaur image generation")

    root_dir = resolve_local_source_dir_for_sync()
    migrate_flat_images_to_v1(
        root_dir,
        default_prompt=dinosaur_image_prompt_template(),
    )
    version_name = resolve_generation_version(root_dir, version)
    output_dir = version_dir(root_dir, version_name)
    meta = ensure_version_meta(
        output_dir,
        default_prompt=dinosaur_image_prompt_template(),
    )
    prompt_template = str(meta.get("prompt") or dinosaur_image_prompt_template())

    existing_stems = scan_existing_stems(output_dir, case_insensitive=True)
    start = time.monotonic()
    counters = GenerateCounters()
    cost_usd = 0.0

    candidates, skipped_existing = _select_candidates(
        session,
        output_dir=output_dir,
        existing_stems=existing_stems,
        dinos=dinos,
    )

    _log_header(
        output_dir=output_dir,
        version=version_name,
        candidates=len(candidates),
        skipped_existing=skipped_existing,
        max_items=max_items,
        dry_run=dry_run,
    )

    for candidate in candidates:
        if max_items is not None and counters.generated >= max_items:
            break

        dinosaur = candidate.dinosaur
        label = (
            f'"{dinosaur.name}" (id={dinosaur.id}) fossils={candidate.fossil_count}'
        )

        if has_local_image(
            output_dir,
            dinosaur.name,
            existing_stems=existing_stems,
            case_insensitive=True,
        ):
            counters.skipped += 1
            logger.info('%s · SKIP · image exists', label)
            continue

        article_text = extract_article_text(dinosaur.article or "")
        if not article_text.strip():
            counters.skipped += 1
            logger.info('%s · SKIP · no article text', label)
            continue

        prompt = build_dinosaur_image_prompt(
            dinosaur.name,
            article_text,
            template=prompt_template,
        )
        output_path = output_png_path(output_dir, dinosaur.name)

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
                existing_stems.add(dinosaur.name.lower())
                counters.generated += 1
                generated = True
                logger.info('%s · OK -> %s/%s', label, version_name, output_path.name)
                break
            except FileExistsError:
                counters.skipped += 1
                existing_stems.add(dinosaur.name.lower())
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
        version=version_name,
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
    version: str,
    candidates: int,
    skipped_existing: int,
    max_items: int | None,
    dry_run: bool,
) -> None:
    logger.info("=== dinosaur_image_generate ===")
    logger.info("version: %s", version)
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
        "version: %s  generated: %d  skipped: %d  failed: %d  elapsed: %.1fs  cost: $%.2f",
        summary.version,
        summary.counters.generated,
        summary.counters.skipped,
        summary.counters.failed,
        summary.elapsed_s,
        summary.cost_usd,
    )
