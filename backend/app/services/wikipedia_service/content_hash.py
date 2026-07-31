"""Content hashing for dinosaur Wikipedia revisions."""

from __future__ import annotations

import hashlib
import json
import re
from dataclasses import dataclass
from typing import Any


_WHITESPACE_RE = re.compile(r"\s+")
_TOKEN_RE = re.compile(r"[a-z0-9]+", re.IGNORECASE)


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


# Append a new revision only when the change clears at least one of these.
_SIGNIFICANT_LENGTH_DELTA_PCT = 15.0
_SIGNIFICANT_TOKEN_JACCARD_MAX = 0.85  # below = more rewritten
_SIGNIFICANT_ABS_CHAR_DELTA = 2_000


@dataclass(frozen=True)
class ArticleChangeMetrics:
    """How much a new Wikipedia parse differs from the previous revision."""

    old_chars: int
    new_chars: int
    char_delta: int
    length_delta_pct: float
    token_jaccard: float
    structural_fields_changed: tuple[str, ...]

    def summary(self) -> str:
        struct = ",".join(self.structural_fields_changed) or "none"
        return (
            f"old_chars={self.old_chars} new_chars={self.new_chars} "
            f"char_delta={self.char_delta:+d} length_delta_pct={self.length_delta_pct:+.1f}% "
            f"token_jaccard={self.token_jaccard:.3f} structural={struct} "
            f"significant={self.is_significant}"
        )

    @property
    def is_significant(self) -> bool:
        """True when the change is large enough to warrant a new revision."""
        if self.structural_fields_changed:
            return True
        if abs(self.length_delta_pct) >= _SIGNIFICANT_LENGTH_DELTA_PCT:
            return True
        if self.token_jaccard < _SIGNIFICANT_TOKEN_JACCARD_MAX:
            return True
        if abs(self.char_delta) >= _SIGNIFICANT_ABS_CHAR_DELTA:
            return True
        return False


def _token_set(text: str) -> set[str]:
    return {m.group(0).lower() for m in _TOKEN_RE.finditer(text)}


def article_change_metrics(
    *,
    old_article: str | None,
    new_article: str | None,
    old_birth: float | None = None,
    new_birth: float | None = None,
    old_death: float | None = None,
    new_death: float | None = None,
    old_period: str | None = None,
    new_period: str | None = None,
    old_diet_type: str | None = None,
    new_diet_type: str | None = None,
    old_cladogram: dict[str, Any] | None = None,
    new_cladogram: dict[str, Any] | None = None,
    old_long_description: str | None = None,
    new_long_description: str | None = None,
) -> ArticleChangeMetrics:
    """Compare previous vs new Wikipedia/parsed payload for logging."""
    old_text = normalize_article_text(old_article)
    new_text = normalize_article_text(new_article)
    old_chars = len(old_text)
    new_chars = len(new_text)
    char_delta = new_chars - old_chars
    if old_chars == 0:
        length_delta_pct = 100.0 if new_chars else 0.0
    else:
        length_delta_pct = (char_delta / old_chars) * 100.0

    old_tokens = _token_set(old_text)
    new_tokens = _token_set(new_text)
    if not old_tokens and not new_tokens:
        token_jaccard = 1.0
    else:
        union = old_tokens | new_tokens
        token_jaccard = (len(old_tokens & new_tokens) / len(union)) if union else 1.0

    changed: list[str] = []
    if old_birth != new_birth:
        changed.append("birth")
    if old_death != new_death:
        changed.append("death")
    if (old_period or "").strip() != (new_period or "").strip():
        changed.append("period")
    if (old_diet_type or "").strip().lower() != (new_diet_type or "").strip().lower():
        changed.append("diet_type")
    if (old_cladogram or {}) != (new_cladogram or {}):
        changed.append("cladogram")
    if (old_long_description or "").strip() != (new_long_description or "").strip():
        changed.append("long_description")

    return ArticleChangeMetrics(
        old_chars=old_chars,
        new_chars=new_chars,
        char_delta=char_delta,
        length_delta_pct=length_delta_pct,
        token_jaccard=token_jaccard,
        structural_fields_changed=tuple(changed),
    )