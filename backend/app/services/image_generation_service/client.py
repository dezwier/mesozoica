"""Gemini Imagen client (OpenAI-compatible endpoint)."""

from __future__ import annotations

import base64
import io
import logging
import time
from typing import Any

import requests
from PIL import Image as PILImage
from PIL import ImageOps

from app.core.config import settings
from app.services.image_generation_service.postprocess import crop_to_portrait_3_4, resize_portrait_cap

logger = logging.getLogger(__name__)

IMAGEN_ULTRA_MODEL_NAME = "imagen-4.0-ultra-generate-001"
IMAGEN_STANDARD_MODEL_NAME = "imagen-4.0-generate-001"
IMAGEN_ULTRA_COST_USD_PER_IMAGE = 0.06
IMAGEN_STANDARD_COST_USD_PER_IMAGE = 0.04
IMAGEN_REQUEST_TIMEOUT_SECONDS = 120
IMAGEN_PORTRAIT_SIZE = "896x1280"
IMAGEN_MAX_ATTEMPTS = 5
IMAGEN_RETRY_BASE_SECONDS = 5.0
INTER_GENERATION_DELAY_SECONDS = 3.0


class ImageGenerationError(RuntimeError):
    """Raised when Imagen image generation fails."""


def generate_image_with_gemini(prompt: str) -> tuple[bytes, dict[str, Any]]:
    """
    Generate a 3:4 portrait image using Gemini Imagen.

    Returns PNG bytes and a usage dict with cost_usd and model_name.
    Retries transient API failures with exponential backoff, then falls back
    from Ultra to standard Imagen when Ultra cannot execute the prompt.
    """
    primary_model = settings.gemini_image_model.strip() or IMAGEN_ULTRA_MODEL_NAME
    try:
        return _generate_with_retries(prompt, model_name=primary_model)
    except ImageGenerationError as primary_exc:
        if primary_model == IMAGEN_STANDARD_MODEL_NAME:
            raise
        if not _should_fallback_to_standard_model(str(primary_exc)):
            raise
        logger.warning(
            "Primary Imagen model %s failed (%s); trying fallback %s",
            primary_model,
            short_generation_error(str(primary_exc)),
            IMAGEN_STANDARD_MODEL_NAME,
        )
        return _generate_with_retries(prompt, model_name=IMAGEN_STANDARD_MODEL_NAME)


def _generate_with_retries(prompt: str, *, model_name: str) -> tuple[bytes, dict[str, Any]]:
    last_error: ImageGenerationError | None = None
    for attempt in range(1, IMAGEN_MAX_ATTEMPTS + 1):
        try:
            return _generate_image_once(prompt, model_name=model_name)
        except ImageGenerationError as exc:
            last_error = exc
            if attempt >= IMAGEN_MAX_ATTEMPTS or not is_retryable_generation_error(str(exc)):
                raise
            delay = IMAGEN_RETRY_BASE_SECONDS * (2 ** (attempt - 1))
            logger.warning(
                "Imagen %s attempt %d/%d failed (%s); retrying in %.0fs",
                model_name,
                attempt,
                IMAGEN_MAX_ATTEMPTS,
                short_generation_error(str(exc)),
                delay,
            )
            time.sleep(delay)
    if last_error is not None:
        raise last_error
    raise ImageGenerationError("Image generation failed")


def _model_cost_usd(model_name: str) -> float:
    if model_name == IMAGEN_STANDARD_MODEL_NAME:
        return IMAGEN_STANDARD_COST_USD_PER_IMAGE
    return IMAGEN_ULTRA_COST_USD_PER_IMAGE


def _generate_image_once(prompt: str, *, model_name: str) -> tuple[bytes, dict[str, Any]]:
    """Single Imagen API request without retries."""
    api_key = settings.google_gemini_api_key.strip()
    if not api_key:
        raise ImageGenerationError(
            "Google Gemini API key not configured. Set GOOGLE_GEMINI_API_KEY."
        )

    model_name = model_name.strip() or IMAGEN_ULTRA_MODEL_NAME
    base_url = "https://generativelanguage.googleapis.com/v1beta/openai/images/generations"
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
    }
    payload = {
        "model": model_name,
        "prompt": prompt,
        "n": 1,
        "response_format": "b64_json",
        "size": IMAGEN_PORTRAIT_SIZE,
    }

    try:
        logger.debug(
            "Imagen request model=%s prompt_len=%d size=%s",
            model_name,
            len(prompt),
            IMAGEN_PORTRAIT_SIZE,
        )
        response = requests.post(
            f"{base_url}?key={api_key}",
            json=payload,
            headers=headers,
            timeout=IMAGEN_REQUEST_TIMEOUT_SECONDS,
        )
        if not response.ok:
            error_msg = _extract_error_message(response)
            raise ImageGenerationError(error_msg)

        data = response.json()
        if "error" in data:
            error_info = data.get("error", {})
            if isinstance(error_info, dict):
                message = error_info.get("message", "Unknown error")
            else:
                message = str(error_info)
            raise ImageGenerationError(f"Gemini API error: {message}")

        if "data" not in data or not data["data"]:
            raise ImageGenerationError(
                f"No image data in response. Keys: {list(data.keys())}"
            )

        first = data["data"][0]
        if "b64_json" not in first:
            raise ImageGenerationError(
                f"Response missing b64_json. Keys: {list(first.keys())}"
            )

        image_bytes = base64.b64decode(first["b64_json"])
        image_bytes = _normalize_to_png_bytes(image_bytes)
        usage: dict[str, Any] = {
            "model_name": model_name,
            "images_generated": 1,
            "cost_usd": _model_cost_usd(model_name),
        }
        return image_bytes, usage

    except requests.exceptions.RequestException as exc:
        raise ImageGenerationError(f"Gemini API request failed: {exc}") from exc
    except ImageGenerationError:
        raise
    except Exception as exc:
        raise ImageGenerationError(f"Failed to generate image: {exc}") from exc


def _normalize_to_png_bytes(image_bytes: bytes) -> bytes:
    """Apply EXIF fix, RGB conversion, and 3:4 crop before saving downstream."""
    img = PILImage.open(io.BytesIO(image_bytes))
    img = ImageOps.exif_transpose(img)
    if img.mode != "RGB":
        img = img.convert("RGB")
    img = crop_to_portrait_3_4(img)
    img = resize_portrait_cap(img)
    buffer = io.BytesIO()
    img.save(buffer, format="PNG", optimize=True)
    return buffer.getvalue()


def _extract_error_message(response: requests.Response) -> str:
    try:
        error_data = response.json()
        error_info = error_data.get("error", {})
        if isinstance(error_info, dict):
            return error_info.get(
                "message",
                f"HTTP {response.status_code}: {response.text[:200]}",
            )
        if error_info:
            return str(error_info)
    except ValueError:
        pass
    return f"HTTP {response.status_code}: {response.text[:500]}"


def is_retryable_generation_error(message: str) -> bool:
    """True for transient Gemini/HTTP failures worth retrying."""
    lower = message.lower()
    if any(code in message for code in ("429", "500", "502", "503", "504")):
        return True
    return any(
        phrase in lower
        for phrase in (
            "service unavailable",
            "service is currently unavailable",
            "resource exhausted",
            "quota exceeded",
            "rate limit",
            "too many requests",
            "timeout",
            "temporarily unavailable",
            "internal error",
            "bad gateway",
            "gateway timeout",
            "fail to execute model",
            "flow-vertex-juno",
            "image generation failed",
        )
    )


def _should_fallback_to_standard_model(message: str) -> bool:
    """Fallback only for model/prompt execution issues, not auth or config errors."""
    lower = message.lower()
    if any(token in message for token in ("401", "403")):
        return False
    if any(
        phrase in lower
        for phrase in (
            "invalid api key",
            "permission denied",
            "not configured",
            "unauthorized",
            "forbidden",
        )
    ):
        return False
    return True


def short_generation_error(message: str) -> str:
    """One-line summary for cron terminal output."""
    text = message.strip()
    for prefix in (
        "Failed to generate image: ",
        "Gemini API error: ",
        "Gemini API request failed: ",
    ):
        if text.startswith(prefix):
            text = text[len(prefix) :]
    lower = text.lower()
    if "quota exceeded" in lower or "exceeded your current quota" in lower:
        return "quota exceeded"
    if "503" in text or "service unavailable" in lower:
        return "service unavailable"
    if "fail to execute model" in lower:
        return "model execution failed"
    if "timeout" in lower:
        return "timeout"
    if len(text) > 120:
        return text[:117] + "..."
    return text
