"""Chat Completions request shaping for OpenAI / Azure OpenAI models.

Ported from learnfromai `app.features.platform.openai_chat`.
"""

from __future__ import annotations


def is_openai_reasoning_model(model: str) -> bool:
    """GPT-5 / o-series use max_completion_tokens and reject custom temperature."""
    key = (model or "").strip().lower()
    return (
        key.startswith("gpt-5")
        or key.startswith("o1")
        or key.startswith("o3")
        or key.startswith("o4")
    )


def openai_chat_body(
    *,
    model: str,
    messages: list[dict],
    max_out: int,
    temperature: float,
    response_format: dict | None = None,
) -> dict:
    body: dict = {
        "model": model,
        "messages": messages,
    }
    if response_format is not None:
        body["response_format"] = response_format
    if is_openai_reasoning_model(model):
        body["max_completion_tokens"] = max_out
    else:
        body["max_tokens"] = max_out
        body["temperature"] = temperature
    return body


def set_openai_max_out(body: dict, max_out: int) -> None:
    if "max_completion_tokens" in body:
        body["max_completion_tokens"] = max_out
    else:
        body["max_tokens"] = max_out
