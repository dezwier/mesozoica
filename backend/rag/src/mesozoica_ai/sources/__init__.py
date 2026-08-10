"""Retrieve and fingerprint external documents."""

from __future__ import annotations

import hashlib
import json
from collections.abc import Mapping, Sequence
from functools import partial
from typing import Any

from pydantic import BaseModel, Field, SecretStr

from .openalex import retrieve_openalex_documents
from .wikipedia import retrieve_wikipedia_documents
from mesozoica_ai.common.models import Document

SUPPORTED_SOURCES = ("wikipedia", "openalex")


class RetrievedDocuments(BaseModel):
    """One normalized source result ready for durable snapshot storage."""

    source: str
    documents: list[Document]
    content_hash: str = Field(min_length=64, max_length=64)
    source_hash: str = Field(min_length=64, max_length=64)
    source_version: str | None = None

    @property
    def serialized_documents(self) -> list[dict[str, Any]]:
        """Return JSON-safe documents suitable for a database JSON column."""
        return [document.model_dump(mode="json") for document in self.documents]


def normalize_sources(sources: Sequence[str] | None = None) -> list[str]:
    """Normalize, deduplicate, and validate requested source names."""
    values = SUPPORTED_SOURCES if not sources else sources
    normalized = [value.strip().casefold() for value in values if value.strip()]
    unknown = sorted(set(normalized) - set(SUPPORTED_SOURCES))
    if unknown:
        raise ValueError(f"Unsupported knowledge sources: {', '.join(unknown)}")
    return list(dict.fromkeys(normalized))


def retrieve_wikipedia(
    title: str,
    *,
    user_agent: str,
    timeout: float | None = None,
    metadata: Mapping[str, Any] | None = None,
) -> RetrievedDocuments:
    """Fetch Wikipedia sections and return fingerprinted documents."""
    documents = retrieve_wikipedia_documents(
        title, user_agent=user_agent, timeout=timeout
    )
    return _fingerprinted("wikipedia", documents, metadata=metadata)


def retrieve_openalex(
    query: str,
    *,
    api_key: str | SecretStr,
    user_agent: str,
    limit: int = 10,
    timeout: float | None = None,
    metadata: Mapping[str, Any] | None = None,
) -> RetrievedDocuments:
    """Fetch OpenAlex works and return fingerprinted documents."""
    documents = retrieve_openalex_documents(
        query,
        api_key=api_key,
        user_agent=user_agent,
        limit=limit,
        timeout=timeout,
    )
    return _fingerprinted("openalex", documents, metadata=metadata)


def bound_wikipedia(*, user_agent: str, timeout: float | None = None):
    """Return retrieve_wikipedia with credentials already bound."""
    return partial(retrieve_wikipedia, user_agent=user_agent, timeout=timeout)


def bound_openalex(
    *,
    api_key: str | SecretStr,
    user_agent: str,
    limit: int = 10,
    timeout: float | None = None,
):
    """Return retrieve_openalex with credentials already bound."""
    return partial(
        retrieve_openalex,
        api_key=api_key,
        user_agent=user_agent,
        limit=limit,
        timeout=timeout,
    )


def require_openalex_credentials(
    sources: Sequence[str] | None,
    *,
    api_key: str | SecretStr | None,
    dry_run: bool = False,
) -> None:
    """Fail fast if OpenAlex is requested without credentials."""
    if dry_run:
        return
    if "openalex" in normalize_sources(list(sources) if sources is not None else None):
        secret = api_key.get_secret_value() if isinstance(api_key, SecretStr) else api_key
        if not secret:
            raise RuntimeError("OPENALEX_API_KEY is required for OpenAlex acquisition")


def _fingerprinted(
    source: str,
    documents: Sequence[Document],
    *,
    metadata: Mapping[str, Any] | None,
) -> RetrievedDocuments:
    enriched = [_with_metadata(document, metadata or {}) for document in documents]
    serialized = [document.model_dump(mode="json") for document in enriched]
    return RetrievedDocuments(
        source=source,
        documents=enriched,
        content_hash=_hash_json(serialized),
        source_hash=_provenance_hash(enriched),
        source_version=_source_version(enriched),
    )


def _with_metadata(document: Document, metadata: Mapping[str, Any]) -> Document:
    if not metadata:
        return document
    return Document.model_validate(
        {
            **document.model_dump(mode="json"),
            "metadata": {
                **document.metadata.model_dump(mode="json", exclude_none=True),
                **metadata,
            },
        }
    )


def _source_version(documents: Sequence[Document]) -> str | None:
    versions = sorted(
        {
            str(document.metadata.source_version)
            for document in documents
            if document.metadata.source_version
        }
    )
    return ",".join(versions)[:255] or None


def _provenance_hash(documents: Sequence[Document]) -> str:
    provenance = [
        {
            "id": document.id,
            "source_id": document.metadata.source_id,
            "source_version": document.metadata.source_version,
            "source_url": document.metadata.source_url,
            "published_at": document.metadata.published_at,
            "updated_at": document.metadata.updated_at,
        }
        for document in documents
    ]
    return _hash_json(provenance)


def _hash_json(value: Any) -> str:
    payload = json.dumps(value, sort_keys=True, ensure_ascii=False, default=str).encode(
        "utf-8"
    )
    return hashlib.sha256(payload).hexdigest()


from mesozoica_ai.sources.acquire import acquire_knowledge, acquire_sources
from mesozoica_ai.sources.store import SqlSnapshotStore

__all__ = [
    "RetrievedDocuments",
    "SUPPORTED_SOURCES",
    "SqlSnapshotStore",
    "acquire_knowledge",
    "acquire_sources",
    "bound_openalex",
    "bound_wikipedia",
    "normalize_sources",
    "require_openalex_credentials",
    "retrieve_openalex",
    "retrieve_wikipedia",
]
