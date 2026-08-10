"""Build RAG documents from a stored dinosaur_type_revision Wikipedia article."""

from __future__ import annotations

import re
from collections.abc import Mapping
from datetime import datetime
from typing import Any
from urllib.parse import quote

from bs4 import BeautifulSoup, NavigableString, Tag

from mesozoica_ai.common.errors import SourceFetchError
from mesozoica_ai.common.models import Document
from mesozoica_ai.sources.helpers import with_metadata

_SKIPPED_SECTIONS = {
    "references",
    "external links",
    "see also",
    "notes",
    "further reading",
    "bibliography",
}
_CHROME_SELECTORS = (
    "script",
    "style",
    "table",
    "sup",
    ".mw-editsection",
    ".navbox",
    ".vertical-navbox",
    ".sisterproject",
    ".metadata",
    ".ambox",
    ".references",
    ".mw-references-wrap",
    ".noprint",
    '[role="navigation"]',
)
_HEADING_TAGS = ("h2", "h3", "h4")
_WS_RE = re.compile(r"\s+")


def wikipedia_documents_from_article(
    article_html: str,
    *,
    title: str,
    page_id: int,
    source_version: str | None = None,
    published_at: datetime | None = None,
    metadata: Mapping[str, Any] | None = None,
) -> list[Document]:
    """Split stored Wikipedia HTML into section ``Document`` values."""
    if not (article_html or "").strip():
        raise SourceFetchError(f"Wikipedia revision has no article text: {title}")
    if not title.strip():
        raise ValueError("Wikipedia title must not be blank")

    sections = _parse_html_sections(article_html)
    page_url = "https://en.wikipedia.org/wiki/" + quote(
        title.strip().replace(" ", "_"), safe="_()"
    )
    documents: list[Document] = []
    for ordinal, (heading, depth, path, text) in enumerate(sections):
        if not text or heading.casefold() in _SKIPPED_SECTIONS:
            continue
        anchor = quote(heading.replace(" ", "_"), safe="_()")
        documents.append(
            Document(
                id=f"wikipedia:{page_id}:section:{ordinal}:{_slug(heading)}",
                text=text,
                metadata={
                    "source": "wikipedia",
                    "source_id": str(page_id),
                    "title": title.strip(),
                    "section": heading,
                    "section_path": path,
                    "section_depth": depth,
                    "section_ordinal": ordinal,
                    "section_anchor": anchor,
                    "source_url": (
                        page_url if heading == "Introduction" else f"{page_url}#{anchor}"
                    ),
                    "published_at": published_at,
                    "updated_at": published_at,
                    "source_version": source_version,
                    "license": "CC BY-SA 4.0",
                    "provenance": "dinosaur_type_revision.article",
                },
            )
        )
    if not documents:
        raise SourceFetchError(f"Wikipedia page has no usable text: {title}")
    return with_metadata(documents, metadata)


def _parse_html_sections(article_html: str) -> list[tuple[str, int, list[str], str]]:
    soup = BeautifulSoup(article_html, "html.parser")
    root = soup.body if soup.body is not None else soup
    for selector in _CHROME_SELECTORS:
        for node in root.select(selector):
            node.decompose()

    headings = [node for node in root.find_all(_HEADING_TAGS) if isinstance(node, Tag)]
    if not headings:
        text = _normalize_text(root.get_text("\n", strip=True))
        return [("Introduction", 0, ["Introduction"], text)] if text else []

    sections: list[tuple[str, int, list[str], str]] = []
    introduction = _text_before(root, headings[0])
    if introduction:
        sections.append(("Introduction", 0, ["Introduction"], introduction))

    path: list[str] = []
    for index, heading in enumerate(headings):
        depth = max(0, int(heading.name[1]) - 1) if heading.name else 1
        label = _heading_label(heading)
        path = path[: max(0, depth - 1)]
        path.append(label)
        end = headings[index + 1] if index + 1 < len(headings) else None
        text = _text_between(heading, end)
        sections.append((label, depth, path.copy(), text))
    return sections


def _heading_label(heading: Tag) -> str:
    span = heading.find("span", class_="mw-headline")
    if isinstance(span, Tag):
        label = span.get_text(" ", strip=True)
        if label:
            return label
    clone = BeautifulSoup(str(heading), "html.parser")
    for node in clone.select(".mw-editsection"):
        node.decompose()
    root = clone.find(_HEADING_TAGS) or clone
    return root.get_text(" ", strip=True) or "Section"


def _text_before(root: Tag, heading: Tag) -> str:
    parts: list[str] = []
    for child in root.children:
        if child is heading:
            break
        if isinstance(child, Tag) and child.name in _HEADING_TAGS:
            break
        if _contains(child, heading):
            parts.append(_text_before(child, heading) if isinstance(child, Tag) else "")
            break
        parts.append(_node_text(child))
    return _normalize_text("\n".join(part for part in parts if part))


def _text_between(heading: Tag, end: Tag | None) -> str:
    parts: list[str] = []
    sibling = heading.next_sibling
    while sibling is not None and sibling is not end:
        if isinstance(sibling, Tag) and sibling.name in _HEADING_TAGS:
            break
        if end is not None and _contains(sibling, end):
            if isinstance(sibling, Tag):
                parts.append(_text_before(sibling, end))
            break
        parts.append(_node_text(sibling))
        sibling = sibling.next_sibling
    return _normalize_text("\n".join(part for part in parts if part))


def _contains(node: Tag | NavigableString, target: Tag) -> bool:
    if not isinstance(node, Tag):
        return False
    return target in node.descendants


def _node_text(node: Tag | NavigableString) -> str:
    if isinstance(node, NavigableString):
        return str(node).strip()
    if isinstance(node, Tag):
        return node.get_text("\n", strip=True)
    return ""


def _normalize_text(text: str) -> str:
    lines = [_WS_RE.sub(" ", line).strip() for line in text.splitlines()]
    return "\n".join(line for line in lines if line).strip()


def _slug(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", value.casefold()).strip("-") or "section"
