"""Normalize knowledge titles/snippets for player-facing display."""

from __future__ import annotations

import html
import re

# Italic-like wrappers OpenAlex / JATS often emit (possibly entity-encoded).
_ITALIC_BLOCK_RE = re.compile(
    r"<(?:i|em|italic)(?:\s[^>]*)?>(.*?)</(?:i|em|italic)>",
    re.IGNORECASE | re.DOTALL,
)
_OTHER_TAG_RE = re.compile(r"</?[^>\s]+(?:\s[^>]*)?>")
_BROKEN_ENTITY_RE = re.compile(
    r"&(?:lt|gt|amp|quot|apos|#\d+|#x[0-9a-fA-F]+)[:;]?",
    re.IGNORECASE,
)
_WS_RE = re.compile(r"\s+")
_ITALIC_OPEN = "\0I\0"
_ITALIC_CLOSE = "\0/I\0"


def clean_display_title(title: str) -> str:
    """Unescape markup and keep italics as ``<i>…</i>`` for rich UI text.

    Ensures a space before/after italic spans when jammed against other words,
    so ``of&lt;i&gt;T. rex&lt;/i&gt;fossils`` becomes ``of <i>T. rex</i> fossils``.
    """
    text = title or ""
    for _ in range(3):
        unescaped = html.unescape(text)
        if unescaped == text:
            break
        text = unescaped

    # Protect italic bodies while stripping other tags.
    protected: list[str] = []

    def _protect(match: re.Match[str]) -> str:
        inner = _WS_RE.sub(" ", match.group(1)).strip()
        protected.append(inner)
        return f"{_ITALIC_OPEN}{len(protected) - 1}{_ITALIC_CLOSE}"

    text = _ITALIC_BLOCK_RE.sub(_protect, text)
    # Mangled leftovers like ``&lt:italic&gt;`` (no proper tag form).
    text = _BROKEN_ENTITY_RE.sub(" ", text)
    # Remaining tags → space so words do not run together.
    text = _OTHER_TAG_RE.sub(" ", text)
    text = _WS_RE.sub(" ", text).strip()

    def _restore(match: re.Match[str]) -> str:
        idx = int(match.group(1))
        inner = protected[idx] if 0 <= idx < len(protected) else ""
        return f"<i>{inner}</i>" if inner else ""

    text = re.sub(
        re.escape(_ITALIC_OPEN) + r"(\d+)" + re.escape(_ITALIC_CLOSE),
        _restore,
        text,
    )
    # Space around italic spans when adjacent to non-space characters.
    text = re.sub(r"(\S)<i>", r"\1 <i>", text)
    text = re.sub(r"</i>(\S)", r"</i> \1", text)
    text = _WS_RE.sub(" ", text).strip()
    return text


def plain_display_title(title: str) -> str:
    """Plain-text form of [clean_display_title] (italics flattened)."""
    return _WS_RE.sub(" ", re.sub(r"</?i>", "", clean_display_title(title))).strip()
