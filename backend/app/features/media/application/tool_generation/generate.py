"""Batch-generate tool card images via Gemini Imagen."""

from __future__ import annotations

import logging
import time

from sqlmodel import Session, col, select

from app.core.config import settings
from app.models.tool_type import ToolType
from app.features.media.application.curated_images.versions import (
    ensure_version_meta,
    require_generation_version,
    version_dir,
)
from app.features.media.infrastructure.image_generation.batch_types import (
    GenerateCounters,
    GenerateSummary,
    generate_exit_code,
)
from app.features.media.infrastructure.image_generation.client import (
    INTER_GENERATION_DELAY_SECONDS,
    short_generation_error,
)
from app.features.media.infrastructure.image_generation.local_files import (
    has_local_image,
    output_png_path,
    scan_existing_stems,
)
from app.features.media.infrastructure.image_generation.prompting import (
    build_tool_image_prompt,
    tool_image_prompt_template,
)
from app.features.media.infrastructure.image_generation.runner import generate_with_retries
from app.features.media.application.tool_images.sync import resolve_local_source_dir_for_sync

logger = logging.getLogger("tool_image_generate")

# Tools use a single attempt (no outer backoff); keep local so behavior is unchanged.
GENERATION_ATTEMPTS = 1

# Re-export shared types for callers/tests that import from this module.
__all__ = [
    "GENERATION_ATTEMPTS",
    "GenerateCounters",
    "GenerateSummary",
    "generate_exit_code",
    "generate_tool_images",
]


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
) -> tuple[list[ToolType], int]:
    stmt = select(ToolType).order_by(ToolType.name)
    tool_filter = _normalize_tool_names(tools)
    if tool_filter is not None:
        stmt = stmt.where(col(ToolType.name).in_(sorted(tool_filter)))

    rows = session.exec(stmt).all()
    skipped_existing = 0
    candidates: list[ToolType] = []
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
    version: str,
) -> GenerateSummary:
    """Generate missing tool card images into a named version folder.

    ``version`` is a required folder name (e.g. ``Original``, ``Summer 26``).
    """
    if not settings.google_gemini_api_key.strip():
        raise RuntimeError("GOOGLE_GEMINI_API_KEY is required for tool image generation")

    root_dir = resolve_local_source_dir_for_sync()
    version_name = require_generation_version(version)
    output_dir = version_dir(root_dir, version_name)
    meta = ensure_version_meta(
        output_dir,
        default_prompt=tool_image_prompt_template(),
    )
    prompt_template = str(meta.get("prompt") or tool_image_prompt_template())

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
        version=version_name,
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
            {
                "name": tool.name,
                "category": tool.category,
                "scientific_tool": tool.scientific_tool,
                "description": tool.description,
                "rarity": tool.rarity,
            },
            template=prompt_template,
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

        outcome = generate_with_retries(
            prompt,
            output_path,
            attempts=GENERATION_ATTEMPTS,
        )
        if outcome.succeeded:
            if outcome.existed:
                counters.skipped += 1
                existing_stems.add(tool.name.lower())
                logger.info('%s · SKIP · image exists', label)
            else:
                cost_usd += outcome.cost_usd
                existing_stems.add(tool.name.lower())
                counters.generated += 1
                logger.info('%s · OK -> %s/%s', label, version_name, output_path.name)
                time.sleep(INTER_GENERATION_DELAY_SECONDS)
        else:
            counters.failed += 1
            logger.error('%s · FAIL · %s', label, short_generation_error(outcome.error))

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


def _log_header(
    *,
    output_dir,
    version: str,
    candidates: int,
    skipped_existing: int,
    max_items: int | None,
    dry_run: bool,
) -> None:
    logger.info("=== tool_image_generate ===")
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
