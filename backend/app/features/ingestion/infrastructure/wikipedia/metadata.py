"""Fetch lightweight Wikipedia page metadata."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime

from dateutil import parser as date_parser

from app.features.ingestion.infrastructure.wikipedia.client import WikipediaClient


@dataclass(frozen=True)
class PageMetadata:
    page_id: int
    title: str
    description: str | None
    is_disambiguation: bool
    article_date: datetime
    image_url: str | None = None


def _parse_timestamp(value: str) -> datetime:
    dt = date_parser.isoparse(value)
    if dt.tzinfo is None:
        return dt.replace(tzinfo=date_parser.tzutc())
    return dt


def _extract_page_image_url(client: WikipediaClient, title: str) -> str | None:
    """Return the lead Wikipedia image URL for a page, if any."""
    data = client.action_api(
        {
            "action": "query",
            "titles": title,
            "prop": "pageimages",
            "piprop": "original|thumbnail",
            "pithumbsize": 800,
        }
    )
    pages = data.get("query", {}).get("pages", {})
    page = next(iter(pages.values()), {})
    original = page.get("original", {})
    if isinstance(original, dict):
        source = original.get("source")
        if source:
            return str(source)
    thumbnail = page.get("thumbnail", {})
    if isinstance(thumbnail, dict):
        source = thumbnail.get("source")
        if source:
            return str(source)
    return None


def fetch_page_metadata(client: WikipediaClient, title: str) -> PageMetadata:
    """Fetch page id, short description, disambiguation flag, and latest revision date."""
    bare = client.page_bare(title)
    page_id = int(bare["id"])
    latest_ts = _parse_timestamp(str(bare["latest"]["timestamp"]))

    desc_data = client.action_api(
        {
            "action": "query",
            "prop": "description|pageprops",
            "titles": title,
            "ppprop": "disambiguation",
        }
    )
    pages = desc_data.get("query", {}).get("pages", {})
    page = next(iter(pages.values()), {})
    description = page.get("description")
    is_disambiguation = "disambiguation" in page.get("pageprops", {})

    return PageMetadata(
        page_id=page_id,
        title=str(bare.get("title", title)),
        description=str(description) if description else None,
        is_disambiguation=is_disambiguation,
        article_date=latest_ts,
        image_url=_extract_page_image_url(client, title),
    )
