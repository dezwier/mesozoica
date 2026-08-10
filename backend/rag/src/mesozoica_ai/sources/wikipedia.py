"""English Wikipedia retrieval with revision-level provenance."""

from __future__ import annotations

import re
from collections.abc import Mapping
from typing import Any
from urllib.parse import quote

from mesozoica_ai.common.errors import SourceFetchError
from mesozoica_ai.common.models import Document as SourceDocument
from mesozoica_ai.sources.documents import with_metadata
from mesozoica_ai.sources.http import RetryingJsonClient

API_URL = "https://en.wikipedia.org/w/api.php"
_HEADING = re.compile(r"(?m)^(==+)\s*(.*?)\s*\1\s*$")
_SKIPPED_SECTIONS = {
    "references", "external links", "see also", "notes", "further reading", "bibliography",
}


def retrieve_wikipedia(
    title: str,
    *,
    user_agent: str,
    timeout: float | None = None,
    metadata: Mapping[str, Any] | None = None,
) -> list[SourceDocument]:
    """Fetch Wikipedia page sections as documents."""
    return with_metadata(
        retrieve_wikipedia_documents(title, user_agent=user_agent, timeout=timeout),
        metadata,
    )


def retrieve_wikipedia_documents(
    title: str, *, user_agent: str, timeout: float | None = None
) -> list[SourceDocument]:
    """Retrieve one Wikipedia page as normalized hierarchical section documents."""
    if not user_agent.strip():
        raise ValueError("Wikipedia requires a descriptive user agent")
    client_options = {} if timeout is None else {
        "connect_timeout_seconds": timeout,
        "read_timeout_seconds": timeout,
    }
    with RetryingJsonClient(**client_options) as client:
        return _retrieve(title, user_agent=user_agent, client=client)


def _retrieve(
    title: str, *, user_agent: str, client: RetryingJsonClient
) -> list[SourceDocument]:
    if not title.strip():
        raise ValueError("Wikipedia title must not be blank")
    payload = client.get(
        API_URL,
        params={
            "action": "query", "prop": "extracts|revisions", "explaintext": True,
            "redirects": True, "titles": title.strip(), "rvprop": "ids|timestamp",
            "format": "json", "formatversion": 2,
        },
        headers={"User-Agent": user_agent},
        source="wikipedia",
    )
    pages = payload.get("query", {}).get("pages", [])
    if not pages or pages[0].get("missing"):
        raise SourceFetchError(f"Wikipedia page not found: {title}")
    page = pages[0]
    canonical_title = str(page["title"])
    page_id = str(page["pageid"])
    revision = (page.get("revisions") or [{}])[0]
    revision_id = revision.get("revid")
    revision_timestamp = revision.get("timestamp")
    page_url = "https://en.wikipedia.org/wiki/" + quote(
        canonical_title.replace(" ", "_"), safe="_()"
    )
    documents: list[SourceDocument] = []
    sections = _parse_sections(str(page.get("extract") or ""))
    for ordinal, (heading, depth, path, text) in enumerate(sections):
        if not text or heading.casefold() in _SKIPPED_SECTIONS:
            continue
        anchor = quote(heading.replace(" ", "_"), safe="_()")
        documents.append(SourceDocument(
            id=f"wikipedia:{page_id}:section:{ordinal}:{_slug(heading)}",
            text=text,
            metadata={
                "source": "wikipedia", "source_id": page_id, "title": canonical_title,
                "section": heading, "section_path": path, "section_depth": depth,
                "section_ordinal": ordinal, "section_anchor": anchor,
                "source_url": f"{page_url}#{anchor}" if heading != "Introduction" else page_url,
                "published_at": revision_timestamp, "updated_at": revision_timestamp,
                "source_version": str(revision_id) if revision_id else None,
                "license": "CC BY-SA 4.0", "provenance": "Wikimedia REST/API extract",
            },
        ))
    if not documents:
        raise SourceFetchError(f"Wikipedia page has no usable text: {title}")
    return documents


def _parse_sections(extract: str) -> list[tuple[str, int, list[str], str]]:
    matches = list(_HEADING.finditer(extract))
    sections: list[tuple[str, int, list[str], str]] = []
    introduction = extract[: matches[0].start()] if matches else extract
    sections.append(("Introduction", 0, ["Introduction"], introduction.strip()))
    path: list[str] = []
    for index, match in enumerate(matches):
        depth = len(match.group(1)) - 1
        heading = match.group(2).strip()
        path = path[: max(0, depth - 1)]
        path.append(heading)
        end = matches[index + 1].start() if index + 1 < len(matches) else len(extract)
        sections.append((heading, depth, path.copy(), extract[match.end():end].strip()))
    return sections


def _slug(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", value.casefold()).strip("-") or "section"
