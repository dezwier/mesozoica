"""List Wikipedia category members."""

from __future__ import annotations

from dataclasses import dataclass

from app.core.config import settings
from app.services.wikipedia_service.client import WikipediaClient


@dataclass(frozen=True)
class CategoryMember:
    page_id: int
    title: str


def list_category_articles(
    client: WikipediaClient,
    category: str | None = None,
    *,
    max_pages: int | None = None,
) -> list[CategoryMember]:
    """Return article titles in a Wikipedia category (namespace 0 only)."""
    cmtitle = category or settings.wikipedia_dinosaur_category
    cap = max_pages if max_pages is not None else settings.wikipedia_sync_max_pages

    members: list[CategoryMember] = []
    continue_token: str | None = None

    while True:
        params: dict[str, str | int] = {
            "action": "query",
            "list": "categorymembers",
            "cmtitle": cmtitle,
            "cmtype": "page",
            "cmnamespace": 0,
            "cmlimit": "max",
        }
        if continue_token:
            params["cmcontinue"] = continue_token

        data = client.action_api(params)
        for item in data.get("query", {}).get("categorymembers", []):
            members.append(
                CategoryMember(
                    page_id=int(item["pageid"]),
                    title=str(item["title"]),
                )
            )
            if cap is not None and len(members) >= cap:
                return members

        cont = data.get("continue", {})
        continue_token = cont.get("cmcontinue")
        if not continue_token:
            break

    return members
