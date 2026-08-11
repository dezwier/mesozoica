"""Normalize knowledge titles/snippets for player-facing display."""

from __future__ import annotations

import html
import re

_TAG_RE = re.compile(r"</?[^>\s]+(?:\s[^>]*)?>")
_BROKEN_ENTITY_RE = re.compile(r"&(?:lt|gt|amp|quot|apos|#\d+|#x[0-9a-fA-F]+)[:;]?", re.I)
_WS_RE = re.compile(r"\s+")


def clean_display_title(title: str) -> str:
    """Strip HTML/XML tags and entities from paper/wiki titles.

    OpenAlex often stores titles like ``&lt;i&gt;Tyrannosaurus&lt;/i&gt; rex``.
    """
    text = title or ""
    for _ in range(3):
        unescaped = html.unescape(text)
        if unescaped == text:
            break
        text = unescaped
    text = _TAG_RE.sub("", text)
    # Catch mangled leftovers such as ``&lt:italic&gt;``.
    text = _BROKEN_ENTITY_RE.sub("", text)
    text = re.sub(r"</?(?:italic|bold)\b[^>]*>", "", text, flags=re.I)
    return _WS_RE.sub(" ", text).strip()
