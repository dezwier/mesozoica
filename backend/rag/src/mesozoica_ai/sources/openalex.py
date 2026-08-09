from __future__ import annotations

from typing import Any

from pydantic import SecretStr

from mesozoica_ai.knowledge.models import KnowledgeDocument

from .http import RetryingJsonClient


class OpenAlexSource:
    API_URL = "https://api.openalex.org/works"

    def __init__(
        self,
        *,
        api_key: str | SecretStr,
        user_agent: str,
        client: RetryingJsonClient | None = None,
    ) -> None:
        key = api_key.get_secret_value() if isinstance(api_key, SecretStr) else api_key
        if not key.strip():
            raise ValueError("OPENALEX_API_KEY is required")
        if not user_agent.strip():
            raise ValueError("OpenAlex requires a descriptive user agent")
        self.api_key = key
        self.user_agent = user_agent
        self.client = client or RetryingJsonClient()

    def search(self, query: str, *, limit: int = 10) -> list[KnowledgeDocument]:
        if not query.strip():
            raise ValueError("OpenAlex query must not be blank")
        if not 1 <= limit <= 100:
            raise ValueError("OpenAlex limit must be between 1 and 100")
        payload = self.client.get(
            self.API_URL,
            params={
                "api_key": self.api_key,
                "search": f'"{query.strip()}"',
                "filter": "is_retracted:false,has_abstract:true,type:article|preprint",
                "per_page": limit,
                "sort": "relevance_score:desc",
            },
            headers={"User-Agent": self.user_agent},
        )
        documents: list[KnowledgeDocument] = []
        for work in payload.get("results", []):
            abstract = reconstruct_abstract(work.get("abstract_inverted_index"))
            if work.get("is_retracted") or not abstract:
                continue
            work_id = str(work.get("id") or "").rsplit("/", 1)[-1]
            title = str(work.get("display_name") or work.get("title") or "").strip()
            if not work_id or not title:
                continue
            authors = [
                str(item.get("author", {}).get("display_name"))
                for item in work.get("authorships", [])
                if item.get("author", {}).get("display_name")
            ]
            source = (work.get("primary_location") or {}).get("source") or {}
            best_location = work.get("best_oa_location") or {}
            documents.append(
                KnowledgeDocument(
                    id=f"openalex:{work_id}",
                    text=abstract,
                    metadata={
                        "source": "openalex",
                        "source_id": work_id,
                        "title": title,
                        "section": "Abstract",
                        "source_url": work.get("doi") or work.get("id"),
                        "published_at": work.get("publication_date"),
                        "updated_at": work.get("updated_date"),
                        "source_version": work.get("updated_date"),
                        "doi": work.get("doi"),
                        "authors": authors,
                        "publication_year": work.get("publication_year"),
                        "venue": source.get("display_name"),
                        "cited_by_count": work.get("cited_by_count", 0),
                        "relevance_score": work.get("relevance_score"),
                        "license": best_location.get("license"),
                    },
                )
            )
        return documents


def reconstruct_abstract(inverted_index: dict[str, list[int]] | None) -> str:
    if not inverted_index:
        return ""
    positioned: list[tuple[int, str]] = []
    for token, positions in inverted_index.items():
        positioned.extend((int(position), token) for position in positions)
    return " ".join(token for _, token in sorted(positioned)).strip()
