from __future__ import annotations

import re
from urllib.parse import quote

from mesozoica_ai.knowledge.models import KnowledgeDocument

from .http import RetryingJsonClient

_HEADING = re.compile(r"(?m)^==+\s*(.*?)\s*==+\s*$")
_SKIPPED_SECTIONS = {
    "references",
    "external links",
    "see also",
    "notes",
    "further reading",
    "bibliography",
}


class WikipediaSource:
    API_URL = "https://en.wikipedia.org/w/api.php"

    def __init__(self, *, user_agent: str, client: RetryingJsonClient | None = None) -> None:
        if not user_agent.strip():
            raise ValueError("Wikipedia requires a descriptive user agent")
        self.user_agent = user_agent
        self.client = client or RetryingJsonClient()

    def fetch(self, title: str) -> list[KnowledgeDocument]:
        if not title.strip():
            raise ValueError("Wikipedia title must not be blank")
        payload = self.client.get(
            self.API_URL,
            params={
                "action": "query",
                "prop": "extracts|revisions",
                "explaintext": True,
                "redirects": True,
                "titles": title.strip(),
                "rvprop": "ids|timestamp",
                "format": "json",
                "formatversion": 2,
            },
            headers={"User-Agent": self.user_agent},
        )
        pages = payload.get("query", {}).get("pages", [])
        if not pages or pages[0].get("missing"):
            raise ValueError(f"Wikipedia page not found: {title}")
        page = pages[0]
        canonical_title = str(page["title"])
        page_id = str(page["pageid"])
        revisions = page.get("revisions") or [{}]
        revision_id = revisions[0].get("revid")
        revision_timestamp = revisions[0].get("timestamp")
        source_url = "https://en.wikipedia.org/wiki/" + quote(
            canonical_title.replace(" ", "_"), safe="_()"
        )
        parts = _HEADING.split(str(page.get("extract") or ""))
        sections = [("Introduction", parts[0]), *zip(parts[1::2], parts[2::2])]
        documents: list[KnowledgeDocument] = []
        for section, text in sections:
            section = section.strip()
            text = text.strip()
            if not text or section.casefold() in _SKIPPED_SECTIONS:
                continue
            section_slug = _slug(section)
            documents.append(
                KnowledgeDocument(
                    id=f"wikipedia:{page_id}:{section_slug}",
                    text=text,
                    metadata={
                        "source": "wikipedia",
                        "source_id": page_id,
                        "title": canonical_title,
                        "section": section,
                        "source_url": source_url,
                        "published_at": revision_timestamp,
                        "updated_at": revision_timestamp,
                        "source_version": str(revision_id) if revision_id else None,
                        "license": "CC BY-SA",
                    },
                )
            )
        if not documents:
            raise ValueError(f"Wikipedia page has no usable text: {title}")
        return documents


def _slug(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", value.casefold()).strip("-") or "section"
