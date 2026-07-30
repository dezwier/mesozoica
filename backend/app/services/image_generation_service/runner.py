"""Shared retry loop for batch image generation jobs."""

from __future__ import annotations

import time
from dataclasses import dataclass
from pathlib import Path

from app.services.image_generation_service.batch_types import (
    GENERATION_ATTEMPTS,
    GENERATION_RETRY_BACKOFF_SECONDS,
)
from app.services.image_generation_service.client import (
    IMAGEN_ULTRA_COST_USD_PER_IMAGE,
    ImageGenerationError,
    generate_image_with_gemini,
)
from app.services.image_generation_service.postprocess import save_processed_png


@dataclass(frozen=True)
class GenerationAttemptOutcome:
    """Result of generate+save with outer retry attempts."""

    succeeded: bool
    existed: bool = False
    cost_usd: float = 0.0
    error: str = ""


def generate_with_retries(
    prompt: str,
    output_path: Path,
    *,
    attempts: int = GENERATION_ATTEMPTS,
    backoff_seconds: float = GENERATION_RETRY_BACKOFF_SECONDS,
) -> GenerationAttemptOutcome:
    """Generate an image and save it, retrying transient failures.

    Returns a structured outcome so callers can update counters, stems, and
    logging without duplicating the retry loop.
    """
    last_error = "unknown error"
    for attempt in range(1, attempts + 1):
        try:
            image_bytes, usage = generate_image_with_gemini(prompt)
            save_processed_png(image_bytes, output_path)
            cost_usd = float(usage.get("cost_usd", IMAGEN_ULTRA_COST_USD_PER_IMAGE))
            return GenerationAttemptOutcome(succeeded=True, cost_usd=cost_usd)
        except FileExistsError:
            return GenerationAttemptOutcome(succeeded=True, existed=True)
        except ImageGenerationError as exc:
            last_error = str(exc)
            if attempt < attempts:
                time.sleep(backoff_seconds * attempt)
        except Exception as exc:
            last_error = str(exc)
            if attempt < attempts:
                time.sleep(backoff_seconds * attempt)
    return GenerationAttemptOutcome(succeeded=False, error=last_error)
