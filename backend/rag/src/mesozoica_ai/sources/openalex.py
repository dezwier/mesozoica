"""OpenAlex abstract retrieval with scholarly provenance."""

from __future__ import annotations

from collections.abc import Mapping
from datetime import date, datetime, time, timezone
from typing import Any

from pydantic import SecretStr

from mesozoica_ai.common.models import Document as SourceDocument
from mesozoica_ai.sources.documents import with_metadata
from mesozoica_ai.sources.http import RetryingJsonClient

API_URL = "https://api.openalex.org/works"


def retrieve_openalex(
    query: str,
    *,
    api_key: str | SecretStr,
    user_agent: str,
    limit: int = 10,
    timeout: float | None = None,
    metadata: Mapping[str, Any] | None = None,
) -> list[SourceDocument]:
    """Fetch OpenAlex works with abstracts as documents."""
    return with_metadata(
        retrieve_openalex_documents(
            query,
            api_key=api_key,
            user_agent=user_agent,
            limit=limit,
            timeout=timeout,
        ),
        metadata,
    )


def retrieve_openalex_documents(
    query: str,
    *,
    api_key: str | SecretStr,
    user_agent: str,
    limit: int = 10,
    timeout: float | None = None,
) -> list[SourceDocument]:
    """Retrieve the highest-relevance non-retracted abstract-bearing works."""
    key = api_key.get_secret_value() if isinstance(api_key, SecretStr) else api_key
    if not key.strip():
        raise ValueError("OPENALEX_API_KEY is required")
    if not user_agent.strip():
        raise ValueError("OpenAlex requires a descriptive user agent")
    client_options = {} if timeout is None else {
        "connect_timeout_seconds": timeout,
        "read_timeout_seconds": timeout,
    }
    with RetryingJsonClient(**client_options) as client:
        return _retrieve(
            query, api_key=key, user_agent=user_agent, limit=limit, client=client
        )


def _retrieve(
    query: str,
    *,
    api_key: str,
    user_agent: str,
    limit: int,
    client: RetryingJsonClient,
) -> list[SourceDocument]:
    if not query.strip():
        raise ValueError("OpenAlex query must not be blank")
    if not 1 <= limit <= 100:
        raise ValueError("OpenAlex limit must be between 1 and 100")
    payload = client.get(
        API_URL,
        params={
            "api_key": api_key,
            "search": f'"{query.strip()}"',
            "filter": "is_retracted:false,has_abstract:true,type:article|preprint",
            "per_page": limit,
            "sort": "relevance_score:desc",
        },
        headers={"User-Agent": user_agent},
        source="openalex",
    )
    documents: list[SourceDocument] = []
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
        documents.append(SourceDocument(
            id=f"openalex:{work_id}",
            text=abstract,
            metadata={
                "source": "openalex", "source_id": work_id, "title": title,
                "section": "Abstract", "source_url": work.get("doi") or work.get("id"),
                "published_at": _as_datetime(work.get("publication_date")),
                "updated_at": _as_datetime(work.get("updated_date")),
                "source_version": work.get("updated_date"), "doi": work.get("doi"),
                "authors": authors, "publication_year": work.get("publication_year"),
                "venue": source.get("display_name"),
                "cited_by_count": work.get("cited_by_count", 0),
                "relevance_score": work.get("relevance_score"),
                "license": best_location.get("license"),
            },
        ))
    return documents


def reconstruct_abstract(inverted_index: dict[str, list[int]] | None) -> str:
    """Reconstruct an abstract from OpenAlex's token-to-position representation."""
    if not inverted_index:
        return ""
    positioned: list[tuple[int, str]] = []
    for token, positions in inverted_index.items():
        positioned.extend((int(position), token) for position in positions)
    return " ".join(token for _, token in sorted(positioned)).strip()


def _as_datetime(value: Any) -> datetime | None:
    if not value:
        return None
    raw = str(value).replace("Z", "+00:00")
    try:
        parsed = datetime.fromisoformat(raw)
    except ValueError:
        try:
            parsed = datetime.combine(date.fromisoformat(raw), time.min)
        except ValueError:
            return None
    return parsed.replace(tzinfo=timezone.utc) if parsed.tzinfo is None else parsed
