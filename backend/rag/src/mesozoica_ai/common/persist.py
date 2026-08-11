"""Persist retrieved documents into normalized knowledge tables."""

from __future__ import annotations

import hashlib
import json
from collections.abc import Callable, Sequence
from typing import Any, Literal

from mesozoica_ai.common.batch import (
    DEFAULT_SUBJECT_KIND,
    JobSummary,
    subject_metadata,
)
from mesozoica_ai.common.checkpoints import (
    acquisition_needed,
    begin_acquisition,
    complete_acquisition,
    fail_acquisition,
)
from mesozoica_ai.common.knowledge_repo import KnowledgeRepository
from mesozoica_ai.common.models import Document

SUPPORTED_SOURCES = ("wikipedia", "openalex")
RetrieveFn = Callable[[Any, str, dict[str, Any]], Sequence[Document]]


def needs_acquisition(
    repo: KnowledgeRepository,
    subject: Any,
    source: str,
    *,
    overwrite: bool = False,
    subject_kind: str = DEFAULT_SUBJECT_KIND,
) -> bool:
    """True when this subject/source is missing or not yet successfully stored."""
    row = repo.get_source(
        subject_kind=subject_kind,
        subject_id=str(subject.id),
        source=source,
    )
    return row is None or acquisition_needed(row, overwrite=overwrite)


def acquire_knowledge(
    repo: KnowledgeRepository,
    *,
    subjects: Sequence[Any],
    retrieve: RetrieveFn,
    sources: Sequence[str] | None = None,
    max_items: int | None = None,
    overwrite: bool = False,
    dry_run: bool = False,
    subject_kind: str = DEFAULT_SUBJECT_KIND,
) -> JobSummary:
    """Retrieve and store documents for each subject/source pair."""
    selected = _normalize_sources(sources)
    selected_subjects = list(subjects[:max_items] if max_items is not None else subjects)
    summary = JobSummary(candidates=len(selected_subjects) * len(selected))
    for subject in selected_subjects:
        for source in selected:
            if dry_run:
                summary.skipped += 1
                continue
            if not needs_acquisition(
                repo,
                subject,
                source,
                overwrite=overwrite,
                subject_kind=subject_kind,
            ):
                summary.skipped += 1
                continue
            metadata = subject_metadata(subject, source)
            try:
                documents = retrieve(subject, source, metadata)
                outcome = store_documents(
                    repo,
                    subject=subject,
                    source=source,
                    documents=documents,
                    overwrite=overwrite,
                    subject_kind=subject_kind,
                )
            except Exception as exc:
                outcome = store_documents(
                    repo,
                    subject=subject,
                    source=source,
                    error=exc,
                    overwrite=overwrite,
                    subject_kind=subject_kind,
                )
            summary.record(outcome)
    return summary


def store_documents(
    repo: KnowledgeRepository,
    *,
    subject: Any,
    source: str,
    documents: Sequence[Document] | None = None,
    error: BaseException | None = None,
    overwrite: bool = False,
    subject_kind: str = DEFAULT_SUBJECT_KIND,
) -> Literal["succeeded", "skipped", "failed"]:
    """Upsert one subject/source and replace its documents."""
    if (documents is None) == (error is None):
        raise ValueError("Provide exactly one of documents or error")

    row = repo.get_or_create_source(
        subject=subject, source=source, subject_kind=subject_kind
    )
    if error is None and not acquisition_needed(row, overwrite=overwrite):
        return "skipped"

    begin_acquisition(row)
    repo.save_source(row)
    repo.commit()

    if error is not None:
        fail_acquisition(row, error)
        repo.save_source(row)
        repo.commit()
        return "failed"

    fingerprinted = _fingerprinted(documents or ())
    changed = complete_acquisition(row, fingerprinted)
    repo.replace_documents(
        row,
        documents or (),
        clear_chunks=changed,
    )
    repo.save_source(row)
    repo.commit()
    repo.refresh(row)
    return "succeeded"


def _normalize_sources(sources: Sequence[str] | None) -> list[str]:
    values = SUPPORTED_SOURCES if not sources else sources
    normalized = [value.strip().casefold() for value in values if value.strip()]
    unknown = sorted(set(normalized) - set(SUPPORTED_SOURCES))
    if unknown:
        raise ValueError(f"Unsupported knowledge sources: {', '.join(unknown)}")
    return list(dict.fromkeys(normalized))


class _Fingerprinted:
    def __init__(
        self,
        *,
        content_hash: str,
        source_hash: str,
        source_version: str | None,
    ) -> None:
        self.content_hash = content_hash
        self.source_hash = source_hash
        self.source_version = source_version


def _fingerprinted(documents: Sequence[Document]) -> _Fingerprinted:
    serialized = [document.model_dump(mode="json") for document in documents]
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
    versions = sorted(
        {
            str(document.metadata.source_version)
            for document in documents
            if document.metadata.source_version
        }
    )
    return _Fingerprinted(
        content_hash=_hash_json(serialized),
        source_hash=_hash_json(provenance),
        source_version=",".join(versions)[:255] or None,
    )


def _hash_json(value: Any) -> str:
    payload = json.dumps(value, sort_keys=True, ensure_ascii=False, default=str).encode(
        "utf-8"
    )
    return hashlib.sha256(payload).hexdigest()
