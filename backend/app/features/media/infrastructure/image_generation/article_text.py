"""Extract plain-text article context for image prompts."""

from __future__ import annotations

import re

from bs4 import BeautifulSoup

from app.core.config import settings


def extract_article_text(html: str, *, max_chars: int | None = None) -> str:
    """
    Strip Wikipedia HTML to lead paragraphs for Imagen prompts.

    Imagen prompts are capped at ~480 tokens; keep the excerpt short.
    """
    cap = max_chars if max_chars is not None else settings.gemini_image_max_article_chars
    if not html or not html.strip():
        return ""

    soup = BeautifulSoup(html, "html.parser")
    for tag in soup(["script", "style", "table", "sup", "ref"]):
        tag.decompose()

    paragraphs: list[str] = []
    for element in soup.find_all(["p", "h2"]):
        if element.name == "h2":
            break
        text = _normalize_whitespace(element.get_text(" ", strip=True))
        if len(text) >= 40:
            paragraphs.append(text)
        if len(paragraphs) >= 3:
            break

    if not paragraphs:
        text = _normalize_whitespace(soup.get_text(" ", strip=True))
        paragraphs = [text] if text else []

    combined = "\n\n".join(paragraphs)
    if len(combined) <= cap:
        return combined
    return combined[: cap - 3].rstrip() + "..."


def _normalize_whitespace(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip()
