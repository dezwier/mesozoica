"""Strip Parsoid HTML to plain text for LLM prompts."""

from __future__ import annotations

from bs4 import BeautifulSoup


def html_to_text(html: str) -> str:
    """Convert HTML article body to normalized plain text."""
    if not html or not html.strip():
        return ""
    soup = BeautifulSoup(html, "html.parser")
    for tag in soup(["script", "style", "noscript"]):
        tag.decompose()
    text = soup.get_text(separator="\n")
    lines = [line.strip() for line in text.splitlines()]
    return "\n".join(line for line in lines if line)
