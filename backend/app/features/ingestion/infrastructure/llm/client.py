"""OpenAI-compatible chat client (httpx), shaped like learnfromai content LLM.

Talks to `OPENAI_BASE_URL` (public OpenAI or Azure Foundry `/openai/v1`).
"""

from __future__ import annotations

import json
import logging
import re
import time
from typing import Any, Optional

import httpx

from app.core.config import settings
from app.features.ingestion.infrastructure.llm.openai_chat import (
    openai_chat_body,
    set_openai_max_out,
)

logger = logging.getLogger(__name__)

OPENAI_REQUEST_TIMEOUT_SECONDS = 120
MAX_JSON_PARSE_ATTEMPTS = 3
MAX_TIMEOUT_RETRY_ATTEMPTS = 3
DEFAULT_MAX_OUTPUT_TOKENS = 4096


def call_openai_api(
    prompt: str,
    system_instruction: Optional[str] = None,
    *,
    model_name: Optional[str] = None,
    max_output_tokens: Optional[int] = None,
    response_mime_type_json: bool = False,
    temperature: Optional[float] = None,
    timeout_seconds: Optional[int] = None,
    log_context: Optional[str] = None,
    # Accepted for call-site compatibility with the old Gemini client; ignored.
    thinking_budget: Optional[int] = None,
    thinking_level: Optional[str] = None,
) -> tuple[dict[str, Any], dict[str, Any]]:
    """
    Call OpenAI chat.completions and return (parsed_json, token_usage).

    Retries on JSON parse failure (up to 3× with token escalation) and HTTP timeout.
    """
    del thinking_budget, thinking_level  # Gemini-only knobs; no-ops on OpenAI.

    api_key = settings.resolved_openai_api_key
    if not api_key:
        raise RuntimeError(
            "OpenAI API key not configured. Set OPENAI_API_KEY "
            "(or AZURE_OPENAI_API_KEY)."
        )

    resolved_model = (model_name or settings.resolved_openai_model).strip()
    if not resolved_model:
        raise RuntimeError(
            "OpenAI model not configured. Set OPENAI_MODEL "
            "(or AZURE_OPENAI_CHAT_DEPLOYMENT)."
        )

    base_url = settings.resolved_openai_base_url.rstrip("/")
    url = f"{base_url}/chat/completions"

    base_for_cap = (
        DEFAULT_MAX_OUTPUT_TOKENS if max_output_tokens is None else int(max_output_tokens)
    )
    temp = settings.openai_temperature if temperature is None else float(temperature)
    max_out = min(base_for_cap, 65536)

    messages: list[dict[str, str]] = []
    if system_instruction:
        messages.append({"role": "system", "content": system_instruction})
    elif response_mime_type_json:
        messages.append(
            {
                "role": "system",
                "content": "You return valid JSON objects only. No markdown fences.",
            }
        )
    messages.append({"role": "user", "content": prompt})

    body = openai_chat_body(
        model=resolved_model,
        messages=messages,
        max_out=max_out,
        temperature=temp,
        response_format={"type": "json_object"} if response_mime_type_json else None,
    )

    last_json_error: Optional[Exception] = None
    extracted_text: Optional[str] = None
    req_timeout = (
        int(timeout_seconds) if timeout_seconds is not None else OPENAI_REQUEST_TIMEOUT_SECONDS
    )

    for attempt in range(1, MAX_JSON_PARSE_ATTEMPTS + 1):
        timeout_tries = 0
        try:
            while True:
                mult = 2 ** (attempt - 1)
                set_openai_max_out(body, min(base_for_cap * mult, 65536))
                extracted_text = None
                try:
                    with httpx.Client(timeout=req_timeout) as client:
                        response = client.post(
                            url,
                            json=body,
                            headers={
                                "Authorization": f"Bearer {api_key}",
                                "api-key": api_key,
                                "Content-Type": "application/json",
                            },
                        )
                    break
                except httpx.TimeoutException:
                    timeout_tries += 1
                    if timeout_tries >= MAX_TIMEOUT_RETRY_ATTEMPTS:
                        logger.error(
                            "OpenAI did not respond within %s seconds after %s attempts%s",
                            req_timeout,
                            timeout_tries,
                            f" ({log_context})" if log_context else "",
                        )
                        raise RuntimeError(
                            f"OpenAI did not respond within {req_timeout} seconds"
                        ) from None
                    logger.warning(
                        "OpenAI timeout (%s/%s) after %ss; retrying request%s",
                        timeout_tries,
                        MAX_TIMEOUT_RETRY_ATTEMPTS,
                        req_timeout,
                        f" ({log_context})" if log_context else "",
                    )
                    time.sleep(0.7 * timeout_tries)

            if response.status_code >= 400:
                detail = _http_error_detail(response)
                raise RuntimeError(
                    f"OpenAI API request failed: HTTP {response.status_code} - {detail}"
                )

            data = response.json()
            usage_payload = data.get("usage") if isinstance(data, dict) else {}
            if not isinstance(usage_payload, dict):
                usage_payload = {}
            prompt_tokens = int(usage_payload.get("prompt_tokens") or 0)
            output_tokens = int(usage_payload.get("completion_tokens") or 0)
            total_tokens = int(
                usage_payload.get("total_tokens") or (prompt_tokens + output_tokens)
            )
            token_usage = {
                "prompt_tokens": prompt_tokens,
                "output_tokens": output_tokens,
                "total_tokens": total_tokens,
                "model_name": resolved_model,
            }

            extracted_text = _extract_message_text(data)
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
                raise RuntimeError(
                    "LLM returned invalid JSON after 3 attempts"
                ) from last_json_error
        except httpx.HTTPStatusError as exc:
            error_msg = f"OpenAI API request failed: {exc}"
            try:
                error_data = exc.response.json()
                error_msg += f" - {error_data}"
            except Exception:
                error_msg += f" - Status: {exc.response.status_code}"
            logger.error(error_msg)
            raise RuntimeError(error_msg) from exc

    raise RuntimeError("LLM returned invalid JSON after 3 attempts") from last_json_error


# Back-compat alias while call sites / tests migrate.
call_gemini_api = call_openai_api


def _extract_message_text(payload: dict[str, Any]) -> str:
    choices = payload.get("choices") or []
    if not isinstance(choices, list) or not choices:
        raise RuntimeError("LLM response missing choices")
    choice = choices[0] if isinstance(choices[0], dict) else {}
    finish = str(choice.get("finish_reason") or "")
    if finish == "content_filter":
        raise RuntimeError("OpenAI blocked the response (content_filter)")
    if finish == "length":
        logger.warning("OpenAI hit output token limit (finish_reason=length)")
    message = choice.get("message") if isinstance(choice.get("message"), dict) else {}
    return str(message.get("content") or "").strip()


def _http_error_detail(response: httpx.Response) -> str:
    try:
        payload = response.json()
    except Exception:
        text = (response.text or "").strip()
        return text[:400] or response.reason_phrase
    if isinstance(payload, dict):
        err = payload.get("error")
        if isinstance(err, dict):
            message = err.get("message") or err.get("code")
            if message:
                return str(message)[:400]
        message = payload.get("message")
        if message:
            return str(message)[:400]
    return re.sub(r"\s+", " ", str(payload))[:400]
