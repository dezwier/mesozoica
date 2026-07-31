"""Content hashing for dinosaur Wikipedia revisions."""

from __future__ import annotations

import hashlib
import json
import re
from typing import Any


_WHITESPACE_RE = re.compile(r"\s+")


def normalize_article_text(article_html: str | None) -> str:
    """Collapse whitespace for stable hashing of article HTML."""
    if not article_html:
        return ""
    return _WHITESPACE_RE.sub(" ", article_html).strip()


def revision_content_hash(
    *,
    article: str | None,
    long_description: str | None = None,
    birth: float | None = None,
    death: float | None = None,
    period: str | None = None,
    diet_type: str | None = None,
    cladogram: dict[str, Any] | None = None,
) -> str:
    """SHA-256 of normalized Wikipedia/parsed payload for a revision."""
    payload = {
        "article": normalize_article_text(article),
        "long_description": (long_description or "").strip(),
        "birth": birth,
        "death": death,
        "period": (period or "").strip(),
        "diet_type": (diet_type or "").strip().lower(),
        "cladogram": cladogram or {},
    }
    raw = json.dumps(payload, sort_keys=True, ensure_ascii=False, separators=(",", ":"))
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()
