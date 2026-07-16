"""Serialize fossil records to compact JSON for image prompts."""

from __future__ import annotations

import json
from decimal import Decimal
from typing import Any

from app.core.config import settings
from app.models.fossil import Fossil

_DEFAULT_STRING_CAP = 400

_IMAGE_PROMPT_LLM_FIELDS: tuple[tuple[str, str], ...] = (
    ("llm_imp_rock_type", "llm_rock_type"),
    ("llm_imp_category", "llm_category"),
    ("llm_imp_subcategory", "llm_subcategory"),
    ("llm_imp_completeness", "llm_completeness"),
    ("llm_imp_preservation_quality", "llm_quality"),
)

# Occurrence-specific PBDB fields useful for LLM enrichment (exclude collection comps/admin noise).
_ENRICHMENT_PROMPT_FIELDS: tuple[str, ...] = (
    "identified_name",
    "genus",
    "pres_mode",
    "occurrence_comments",
    "feed_pred_traces",
    "preservation_comments",
    "fragmentation",
    "preservation_quality",
    "lagerstatten",
    "lithdescript",
    "lithology1",
    "lithology2",
    "lithadj1",
    "stratcomments",
    "geological_formation",
    "early_interval",
    "late_interval",
    "min_age_ma",
    "max_age_ma",
    "environment",
    "country_code",
    "state",
    "geogcomments",
)


def fossil_to_prompt_dict(fossil: Fossil, *, dinosaur_name: str) -> dict[str, Any]:
    """Return non-null fossil fields plus dinosaur name (full record)."""
    raw = fossil.model_dump()
    payload: dict[str, Any] = {"dinosaur_name": dinosaur_name}
    for key, value in raw.items():
        if value is None or key in {"main_image_url", "description"}:
            continue
        payload[key] = _serialize_value(value)
    return payload


def fossil_to_enrichment_prompt_dict(fossil: Fossil, *, dinosaur_name: str) -> dict[str, Any]:
    """Return occurrence-specific fossil fields for LLM enrichment prompts."""
    source = fossil_to_prompt_dict(fossil, dinosaur_name=dinosaur_name)
    payload: dict[str, Any] = {"dinosaur_name": dinosaur_name}
    for key in _ENRICHMENT_PROMPT_FIELDS:
        value = source.get(key)
        if value is None:
            continue
        payload[key] = _serialize_value(value)
    return payload


def fossil_to_image_prompt_dict(fossil: Fossil, *, dinosaur_name: str) -> dict[str, Any]:
    """Return only LLM enrichment fields used for fossil image generation."""
    payload: dict[str, Any] = {"dinosaur": dinosaur_name}
    for model_field, prompt_key in _IMAGE_PROMPT_LLM_FIELDS:
        value = getattr(fossil, model_field, None)
        if value is None:
            continue
        text = str(value).strip()
        if not text:
            continue
        payload[prompt_key] = text
    return payload


def fossil_to_image_prompt_json(
    fossil: Fossil,
    *,
    dinosaur_name: str,
    max_chars: int | None = None,
) -> str:
    """Compact JSON for fossil image prompts."""
    cap = max_chars if max_chars is not None else settings.gemini_image_max_fossil_json_chars
    payload = fossil_to_image_prompt_dict(fossil, dinosaur_name=dinosaur_name)
    text = json.dumps(payload, ensure_ascii=False, separators=(",", ":"))
    if len(text) <= cap:
        return text
    return _truncate_fossil_payload(payload, cap)


def fossil_to_prompt_json(
    fossil: Fossil,
    *,
    dinosaur_name: str,
    max_chars: int | None = None,
) -> str:
    """Compact JSON string for fossil image prompts, truncated if needed."""
    return fossil_to_image_prompt_json(
        fossil,
        dinosaur_name=dinosaur_name,
        max_chars=max_chars,
    )


def _serialize_value(value: Any) -> Any:
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, str):
        if len(value) > _DEFAULT_STRING_CAP:
            return value[: _DEFAULT_STRING_CAP - 3].rstrip() + "..."
        return value
    return value


def _truncate_fossil_payload(payload: dict[str, Any], cap: int) -> str:
    """Progressively drop long text fields until JSON fits the cap."""
    trimmed = dict(payload)
    long_keys = sorted(
        (key for key, value in trimmed.items() if isinstance(value, str) and len(value) > 120),
        key=lambda key: len(str(trimmed[key])),
        reverse=True,
    )
    for key in long_keys:
        value = str(trimmed[key])
        trimmed[key] = value[:120].rstrip() + "..."
        text = json.dumps(trimmed, ensure_ascii=False, separators=(",", ":"))
        if len(text) <= cap:
            return text

    text = json.dumps(trimmed, ensure_ascii=False, separators=(",", ":"))
    if len(text) <= cap:
        return text
    return text[: cap - 3].rstrip() + "..."
