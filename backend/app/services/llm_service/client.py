"""Gemini REST client (httpx), ported from archipelago llm_service."""

from __future__ import annotations

import json
import logging
import time
from typing import Any, Optional

import httpx

from app.core.config import settings

logger = logging.getLogger(__name__)

GEMINI_REQUEST_TIMEOUT_SECONDS = 60
MAX_JSON_PARSE_ATTEMPTS = 3
MAX_TIMEOUT_RETRY_ATTEMPTS = 3
DEFAULT_MAX_OUTPUT_TOKENS = 4096


def call_gemini_api(
    prompt: str,
    system_instruction: Optional[str] = None,
    *,
    model_name: Optional[str] = None,
    max_output_tokens: Optional[int] = None,
    response_mime_type_json: bool = False,
    temperature: Optional[float] = None,
    timeout_seconds: Optional[int] = None,
    log_context: Optional[str] = None,
) -> tuple[dict[str, Any], dict[str, Any]]:
    """
    Call Gemini generateContent and return (parsed_json, token_usage).

    Retries on JSON parse failure (up to 3× with token escalation) and HTTP timeout.
    """
    api_key = settings.google_gemini_api_key
    if not api_key:
        raise RuntimeError("Google Gemini API key not configured")

    resolved_model = model_name or settings.gemini_model
    base_url = (
        f"https://generativelanguage.googleapis.com/v1beta/models/"
        f"{resolved_model}:generateContent"
    )

    base_for_cap = DEFAULT_MAX_OUTPUT_TOKENS if max_output_tokens is None else int(max_output_tokens)
    temp = settings.gemini_temperature if temperature is None else float(temperature)
    generation_config: dict[str, Any] = {
        "temperature": temp,
        "topK": 40,
        "topP": 0.95,
        "maxOutputTokens": min(base_for_cap, 65536),
    }
    if response_mime_type_json:
        generation_config["responseMimeType"] = "application/json"

    payload: dict[str, Any] = {
        "contents": [{"parts": [{"text": prompt}]}],
        "generationConfig": generation_config,
    }
    if system_instruction:
        payload["systemInstruction"] = {"parts": [{"text": system_instruction}]}

    last_json_error: Optional[Exception] = None
    extracted_text: Optional[str] = None
    req_timeout = int(timeout_seconds) if timeout_seconds is not None else GEMINI_REQUEST_TIMEOUT_SECONDS

    for attempt in range(1, MAX_JSON_PARSE_ATTEMPTS + 1):
        timeout_tries = 0
        try:
            while True:
                mult = 2 ** (attempt - 1)
                payload["generationConfig"]["maxOutputTokens"] = min(base_for_cap * mult, 65536)
                extracted_text = None
                try:
                    with httpx.Client(timeout=req_timeout) as client:
                        response = client.post(
                            f"{base_url}?key={api_key}",
                            json=payload,
                            headers={"Content-Type": "application/json"},
                        )
                    break
                except httpx.TimeoutException:
                    timeout_tries += 1
                    if timeout_tries >= MAX_TIMEOUT_RETRY_ATTEMPTS:
                        logger.error(
                            "Gemini did not respond within %s seconds after %s attempts%s",
                            req_timeout,
                            timeout_tries,
                            f" ({log_context})" if log_context else "",
                        )
                        raise RuntimeError(
                            f"Gemini did not respond within {req_timeout} seconds"
                        ) from None
                    logger.warning(
                        "Gemini timeout (%s/%s) after %ss; retrying request%s",
                        timeout_tries,
                        MAX_TIMEOUT_RETRY_ATTEMPTS,
                        req_timeout,
                        f" ({log_context})" if log_context else "",
                    )
                    time.sleep(0.7 * timeout_tries)

            response.raise_for_status()
            data = response.json()

            usage_metadata = data.get("usageMetadata", {})
            prompt_tokens = usage_metadata.get("promptTokenCount", 0)
            output_tokens = usage_metadata.get("candidatesTokenCount", 0)
            total_tokens = usage_metadata.get("totalTokenCount", prompt_tokens + output_tokens)
            token_usage = {
                "prompt_tokens": prompt_tokens,
                "output_tokens": output_tokens,
                "total_tokens": total_tokens,
                "model_name": resolved_model,
            }

            if "candidates" not in data or len(data["candidates"]) == 0:
                raise RuntimeError("LLM response missing candidates")

            candidate = data["candidates"][0]
            finish_reason = candidate.get("finishReason")
            if finish_reason == "MAX_TOKENS":
                logger.warning(
                    "Gemini hit output token limit (finishReason=MAX_TOKENS); "
                    "response may be truncated",
                )
            if "content" not in candidate or "parts" not in candidate["content"]:
                raise RuntimeError("LLM response missing content or parts")

            extracted_text = candidate["content"]["parts"][0].get("text", "").strip()
            if not extracted_text:
                raise RuntimeError("LLM returned empty response")

            if extracted_text.startswith("```"):
                lines = extracted_text.split("\n")
                extracted_text = (
                    "\n".join(lines[1:-1]) if lines[0].startswith("```") else extracted_text
                )
                if extracted_text.endswith("```"):
                    extracted_text = extracted_text[:-3]

            llm_data = json.loads(extracted_text)
            if not isinstance(llm_data, dict):
                raise json.JSONDecodeError("Expected JSON object", extracted_text, 0)
            return llm_data, token_usage

        except json.JSONDecodeError as exc:
            last_json_error = exc
            logger.error(
                "Failed to parse LLM JSON response (attempt %d/%d): %s",
                attempt,
                MAX_JSON_PARSE_ATTEMPTS,
                exc,
            )
            snippet = (extracted_text or "(not available)")[:500]
            logger.error("Response text (first 500 chars): %s", snippet)
            if attempt < MAX_JSON_PARSE_ATTEMPTS:
                time.sleep(min(3.0, 0.6 * attempt))
            else:
                raise RuntimeError("LLM returned invalid JSON after 3 attempts") from last_json_error
        except httpx.HTTPStatusError as exc:
            error_msg = f"Gemini API request failed: {exc}"
            try:
                error_data = exc.response.json()
                error_msg += f" - {error_data}"
            except Exception:
                error_msg += f" - Status: {exc.response.status_code}"
            logger.error(error_msg)
            raise RuntimeError(error_msg) from exc

    raise RuntimeError("LLM returned invalid JSON after 3 attempts") from last_json_error
