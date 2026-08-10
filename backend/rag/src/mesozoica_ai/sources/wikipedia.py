"""English Wikipedia section source with revision-level provenance."""

from __future__ import annotations

import re
from urllib.parse import quote

from .errors import SourceFetchError
from .http import RetryingJsonClient
from .models import SourceDocument

_HEADING = re.compile(r"(?m)^(==+)\s*(.*?)\s*\1\s*$")
_SKIPPED_SECTIONS = {
    "references", "external links", "see also", "notes", "further reading", "bibliography",
}


class WikipediaSource:
    """Fetch one page as hierarchical section documents."""

    API_URL = "https://en.wikipedia.org/w/api.php"

    def __init__(self, *, user_agent: str, client: RetryingJsonClient | None = None) -> None:
        if not user_agent.strip():
            raise ValueError("Wikipedia requires a descriptive user agent")
        self.user_agent = user_agent
        self.client = client or RetryingJsonClient()
        self._owns_client = client is None

    def __enter__(self) -> "WikipediaSource":
        return self

    def __exit__(self, *_: object) -> None:
        self.close()

    def close(self) -> None:
        """Close the internally-created HTTP client."""
        if self._owns_client:
            self.client.close()

    def fetch(self, title: str) -> list[SourceDocument]:
        """Fetch a page and preserve section depth, path, ordinal, anchor, and revision."""
        if not title.strip():
            raise ValueError("Wikipedia title must not be blank")
        payload = self.client.get(
            self.API_URL,
            params={
                "action": "query", "prop": "extracts|revisions", "explaintext": True,
                "redirects": True, "titles": title.strip(), "rvprop": "ids|timestamp",
                "format": "json", "formatversion": 2,
            },
            headers={"User-Agent": self.user_agent},
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
        for ordinal, (heading, depth, path, text) in enumerate(_parse_sections(str(page.get("extract") or ""))):
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
