"""Batch-generate tool card images via Gemini Imagen."""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field

from sqlmodel import Session, col, select

from app.core.config import settings
from app.models.tool import Tool
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
from app.services.image_generation_service.prompting import build_tool_image_prompt
from app.services.tool_image_service.sync import resolve_local_source_dir_for_sync

logger = logging.getLogger("tool_image_generate")

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


def _normalize_tool_names(tools: list[str] | None) -> set[str] | None:
    if not tools:
        return None
    normalized = {(name or "").strip() for name in tools}
    normalized.discard("")
    return normalized or None


def _select_candidates(
    session: Session,
    *,
    output_dir,
    existing_stems: set[str],
    tools: list[str] | None = None,
) -> tuple[list[Tool], int]:
    stmt = select(Tool).order_by(Tool.name)
    tool_filter = _normalize_tool_names(tools)
    if tool_filter is not None:
        stmt = stmt.where(col(Tool.name).in_(sorted(tool_filter)))

    rows = session.exec(stmt).all()
    skipped_existing = 0
    candidates: list[Tool] = []
    for tool in rows:
        if has_local_image(
            output_dir,
            tool.name,
            existing_stems=existing_stems,
            case_insensitive=True,
        ):
            skipped_existing += 1
            continue
        candidates.append(tool)
    return candidates, skipped_existing


def generate_tool_images(
    session: Session,
    *,
    dry_run: bool = False,
    max_items: int | None = None,
    tools: list[str] | None = None,
) -> GenerateSummary:
    """Generate missing tool card images to the local repo folder."""
    if not settings.google_gemini_api_key.strip():
        raise RuntimeError("GOOGLE_GEMINI_API_KEY is required for tool image generation")

    output_dir = resolve_local_source_dir_for_sync()
    existing_stems = scan_existing_stems(output_dir, case_insensitive=True)
    start = time.monotonic()
    counters = GenerateCounters()
    cost_usd = 0.0

    candidates, skipped_existing = _select_candidates(
        session,
        output_dir=output_dir,
        existing_stems=existing_stems,
        tools=tools,
    )

    _log_header(
        output_dir=output_dir,
        candidates=len(candidates),
        skipped_existing=skipped_existing,
        max_items=max_items,
        dry_run=dry_run,
    )

    for tool in candidates:
        if max_items is not None and counters.generated >= max_items:
            break

        label = f'"{tool.name}" (id={tool.id})'

        if has_local_image(
            output_dir,
            tool.name,
            existing_stems=existing_stems,
            case_insensitive=True,
        ):
            counters.skipped += 1
            logger.info('%s · SKIP · image exists', label)
            continue

        prompt = build_tool_image_prompt(
            name=tool.name,
            scientific_tool=tool.scientific_tool,
            category=tool.category,
            description=tool.description,
        )
        output_path = output_png_path(output_dir, tool.name)

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
                existing_stems.add(tool.name.lower())
                counters.generated += 1
                generated = True
                logger.info('%s · OK -> %s', label, output_path.name)
                break
            except FileExistsError:
                counters.skipped += 1
                existing_stems.add(tool.name.lower())
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
    logger.info("=== tool_image_generate ===")
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
