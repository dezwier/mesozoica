"""Resolve a Wikipedia page revision as of a given timestamp."""

from __future__ import annotations

from datetime import datetime, timezone

from app.features.ingestion.infrastructure.wikipedia.client import WikipediaClient


def revision_as_of(
    client: WikipediaClient,
    *,
    title: str,
    as_of: datetime,
) -> int | None:
    """Return the page's latest revision id at or before ``as_of``, if any.

    Follows redirects. Returns ``None`` when the page has no revision at or
    before the timestamp (e.g. the article was created later).
    """
    if as_of.tzinfo is None:
        as_of = as_of.replace(tzinfo=timezone.utc)
    else:
        as_of = as_of.astimezone(timezone.utc)

    data = client.action_api(
        {
            "action": "query",
            "titles": title,
            "redirects": 1,
            "prop": "revisions",
            "rvprop": "ids|timestamp",
            "rvlimit": 1,
            "rvstart": as_of.strftime("%Y-%m-%dT%H:%M:%SZ"),
            "rvdir": "older",
        }
    )
    pages = data.get("query", {}).get("pages", {})
    page = next(iter(pages.values()), {})
    if not isinstance(page, dict) or page.get("missing") is not None:
        return None
    revisions = page.get("revisions") or []
    if not revisions:
        return None
    revid = revisions[0].get("revid")
    return int(revid) if revid is not None else None
