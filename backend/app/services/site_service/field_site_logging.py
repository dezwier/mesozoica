"""Structured logging helpers for field-site ensure/generate."""

from __future__ import annotations

import logging
from typing import Any

logger = logging.getLogger("field_site_generate")

FIELD_ENSURE_REASONS = frozenset({"resume", "move_500m", "field_mode_on"})


def normalize_reason(reason: str | None) -> str | None:
    if reason is None:
        return None
    trimmed = reason.strip()
    if not trimmed:
        return None
    if trimmed in FIELD_ENSURE_REASONS:
        return trimmed
    return trimmed[:32]


def log_field_event(action: str, **fields: Any) -> None:
    """Emit a single grep-friendly log line: field_site_generate action=… k=v …"""
    parts = [f"field_site_generate action={action}"]
    for key, value in fields.items():
        if value is None:
            continue
        parts.append(f"{key}={value}")
    logger.info(" ".join(parts))
