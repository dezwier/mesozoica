"""List Wikipedia category members."""

from __future__ import annotations

from dataclasses import dataclass

from app.core.config import settings
from app.services.wikipedia_service.client import WikipediaClient


@dataclass(frozen=True)
class CategoryMember:
    page_id: int
    title: str


def default_wikipedia_dinosaur_categories() -> list[str]:
    """Default Wikipedia categories used by the dinosaur sync job."""
    categories = [
        settings.wikipedia_dinosaur_category,
        settings.wikipedia_feathered_dinosaur_category,
    ]
    return [category.strip() for category in categories if category.strip()]


def merge_category_members(*member_lists: list[CategoryMember]) -> list[CategoryMember]:
    """Merge category member lists, deduplicating by page id then title."""
    seen_page_ids: set[int] = set()
    seen_titles: set[str] = set()
    merged: list[CategoryMember] = []

    for members in member_lists:
        for member in members:
            if member.page_id and member.page_id in seen_page_ids:
                continue
            title_key = member.title.casefold()
            if title_key in seen_titles:
                continue
            if member.page_id:
                seen_page_ids.add(member.page_id)
            seen_titles.add(title_key)
            merged.append(member)

    return merged


def list_dinosaur_sync_batches(
    client: WikipediaClient,
    *,
    category: str | None = None,
    max_pages: int | None = None,
) -> list[tuple[str, list[CategoryMember]]]:
    """Return sync batches per category, processed in order with deduplication."""
    if category is not None:
        return [
            (category, list_category_articles(client, category, max_pages=max_pages)),
        ]

    batches: list[tuple[str, list[CategoryMember]]] = []
    seen_page_ids: set[int] = set()
    seen_titles: set[str] = set()
    remaining = max_pages

    for cat in default_wikipedia_dinosaur_categories():
        members = list_category_articles(client, cat, max_pages=None)
        batch: list[CategoryMember] = []
        for member in members:
            if member.page_id and member.page_id in seen_page_ids:
                continue
            title_key = member.title.casefold()
            if title_key in seen_titles:
                continue
            if member.page_id:
                seen_page_ids.add(member.page_id)
            seen_titles.add(title_key)
            batch.append(member)
            if remaining is not None:
                remaining -= 1
                if remaining <= 0:
                    break
        if batch:
            batches.append((cat, batch))
        if remaining is not None and remaining <= 0:
            break

    return batches


def list_dinosaur_sync_candidates(
    client: WikipediaClient,
    *,
    category: str | None = None,
    max_pages: int | None = None,
) -> list[CategoryMember]:
    """Return a flat, deduplicated candidate list (all default categories merged)."""
    batches = list_dinosaur_sync_batches(
        client,
        category=category,
        max_pages=max_pages,
    )
    return merge_category_members(*(members for _, members in batches))


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
