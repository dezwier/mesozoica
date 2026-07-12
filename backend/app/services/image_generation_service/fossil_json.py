"""Serialize fossil records to compact JSON for image prompts."""

from __future__ import annotations

import json
import re
from decimal import Decimal
from typing import Any

from app.core.config import settings
from app.models.fossil import Fossil

_DEFAULT_STRING_CAP = 400

# Fields that help Imagen depict the fossil and dig site (priority order).
_IMAGE_PROMPT_FIELD_ORDER: tuple[str, ...] = (
    "dinosaur_name",
    "identified_name",
    "pres_mode",
    "common_body_parts",
    "rare_body_parts",
    "articulated_parts",
    "associated_parts",
    "component_comments",
    "occurrence_comments",
    "feed_pred_traces",
    "preservation_quality",
    "fragmentation",
    "composition",
    "architecture",
    "size_classes",
    "geological_formation",
    "early_interval",
    "min_age_ma",
    "max_age_ma",
    "lithdescript",
    "lithology1",
    "lithadj1",
    "stratcomments",
    "environment",
    "country_code",
    "state",
    "geogcomments",
    "collection_name",
    "collection_aka",
)

_CATALOG_NUMBER_RE = re.compile(
    r"^[A-Z]{1,6}[\s-]?\d[\w./-]*$",
    re.IGNORECASE,
)
_ANATOMY_HINTS = (
    "skull",
    "vertebra",
    "femur",
    "tibia",
    "tooth",
    "teeth",
    "bone",
    "bones",
    "partial",
    "articulated",
    "fragment",
    "rib",
    "limb",
    "track",
    "trace",
    "impression",
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


def fossil_to_image_prompt_dict(fossil: Fossil, *, dinosaur_name: str) -> dict[str, Any]:
    """Return only image-relevant fossil fields, omitting empty or catalog-only values."""
    source = fossil_to_prompt_dict(fossil, dinosaur_name=dinosaur_name)
    payload: dict[str, Any] = {}

    for key in _IMAGE_PROMPT_FIELD_ORDER:
        value = source.get(key)
        if not _is_informative_value(key, value):
            continue
        payload[key] = _serialize_value(value)

    if not payload:
        payload["dinosaur_name"] = dinosaur_name
        if source.get("pres_mode"):
            payload["pres_mode"] = source["pres_mode"]

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


def _is_informative_value(key: str, value: Any) -> bool:
    if value is None:
        return False
    if isinstance(value, str):
        stripped = value.strip()
        if not stripped:
            return False
        if key in {"occurrence_comments", "component_comments"}:
            return _is_informative_comment(stripped)
        if key == "fossilsfrom1" and stripped.upper() in {"Y", "N"}:
            return False
        return True
    return True


def _is_informative_comment(text: str) -> bool:
    if len(text) >= 40:
        return True
    lower = text.lower()
    if any(hint in lower for hint in _ANATOMY_HINTS):
        return True
    if _CATALOG_NUMBER_RE.match(text.strip()):
        return False
    words = [word for word in re.split(r"\s+", text) if word]
    if len(words) <= 3 and sum(1 for char in text if char.isupper()) / max(len(text), 1) > 0.35:
        return False
    return len(text) >= 15


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
