"""Gemini Imagen client (OpenAI-compatible endpoint)."""

from __future__ import annotations

import base64
import io
import logging
from typing import Any

import requests
from PIL import Image as PILImage
from PIL import ImageOps

from app.core.config import settings
from app.services.image_generation_service.postprocess import crop_to_portrait_3_4, resize_portrait_cap

logger = logging.getLogger(__name__)

IMAGEN_ULTRA_MODEL_NAME = "imagen-4.0-ultra-generate-001"
IMAGEN_ULTRA_COST_USD_PER_IMAGE = 0.06
IMAGEN_REQUEST_TIMEOUT_SECONDS = 120
IMAGEN_PORTRAIT_SIZE = "896x1280"


class ImageGenerationError(RuntimeError):
    """Raised when Imagen image generation fails."""


def generate_image_with_gemini(prompt: str) -> tuple[bytes, dict[str, Any]]:
    """
    Generate a 3:4 portrait image using Gemini Imagen.

    Returns PNG bytes and a usage dict with cost_usd and model_name.
    """
    api_key = settings.google_gemini_api_key.strip()
    if not api_key:
        raise ImageGenerationError(
            "Google Gemini API key not configured. Set GOOGLE_GEMINI_API_KEY."
        )

    model_name = settings.gemini_image_model.strip() or IMAGEN_ULTRA_MODEL_NAME
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
            "cost_usd": IMAGEN_ULTRA_COST_USD_PER_IMAGE,
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
    if "timeout" in lower:
        return "timeout"
    if len(text) > 120:
        return text[:117] + "..."
    return text
