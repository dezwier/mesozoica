"""Resumable acquisition and indexing checkpoint transitions."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Protocol


class AcquiredDocuments(Protocol):
    """Duck-typed acquisition payload stored on a checkpoint."""

    content_hash: str
    source_hash: str
    source_version: str | None
    serialized_documents: list[dict[str, Any]]


class AcquisitionCheckpoint(Protocol):
    """Mutable fields required by the acquisition state machine."""

    documents: list[dict[str, Any]]
    source_version: str | None
    source_hash: str | None
    content_hash: str | None
    indexed_hash: str | None
    indexed_pipeline_fingerprint: str | None
    acquisition_status: str
    index_status: str
    acquisition_attempts: int
    acquisition_error: str | None
    index_error: str | None
    acquisition_started_at: datetime | None
    acquisition_finished_at: datetime | None
    updated_at: datetime


class IndexCheckpoint(Protocol):
    """Mutable fields required by the indexing state machine."""

    content_hash: str | None
    indexed_hash: str | None
    indexed_pipeline_fingerprint: str | None
    index_status: str
    index_attempts: int
    index_error: str | None
    index_started_at: datetime | None
    index_finished_at: datetime | None
    updated_at: datetime


def acquisition_needed(
    checkpoint: AcquisitionCheckpoint, *, overwrite: bool = False
) -> bool:
    """Return whether a source checkpoint should be acquired or retried."""
    return overwrite or checkpoint.acquisition_status != "succeeded"


def begin_acquisition(
    checkpoint: AcquisitionCheckpoint, *, now: datetime | None = None
) -> None:
    """Mark a checkpoint running before the external request starts."""
    timestamp = now or _utc_now()
    checkpoint.acquisition_status = "running"
    checkpoint.acquisition_attempts += 1
    checkpoint.acquisition_started_at = timestamp
    checkpoint.acquisition_finished_at = None
    checkpoint.acquisition_error = None
    checkpoint.updated_at = timestamp


def complete_acquisition(
    checkpoint: AcquisitionCheckpoint,
    result: AcquiredDocuments,
    *,
    now: datetime | None = None,
) -> bool:
    """Store a successful result and invalidate indexing only when content changed."""
    changed = checkpoint.content_hash != result.content_hash
    checkpoint.documents = result.serialized_documents
    checkpoint.content_hash = result.content_hash
    checkpoint.source_hash = result.source_hash
    checkpoint.source_version = result.source_version
    checkpoint.acquisition_status = "succeeded"
    checkpoint.acquisition_finished_at = now or _utc_now()
    checkpoint.acquisition_error = None
    if changed:
        checkpoint.index_status = "pending"
        checkpoint.indexed_hash = None
        checkpoint.indexed_pipeline_fingerprint = None
        checkpoint.index_error = None
    checkpoint.updated_at = checkpoint.acquisition_finished_at
    return changed


def fail_acquisition(
    checkpoint: AcquisitionCheckpoint,
    error: Exception,
    *,
    now: datetime | None = None,
) -> None:
    """Record a retryable acquisition failure without hiding prior snapshot data."""
    timestamp = now or _utc_now()
    checkpoint.acquisition_status = "failed"
    checkpoint.acquisition_finished_at = timestamp
    checkpoint.acquisition_error = str(error)[:4000]
    checkpoint.updated_at = timestamp


def indexing_needed(
    checkpoint: IndexCheckpoint,
    *,
    pipeline_fingerprint: str,
    overwrite: bool = False,
) -> bool:
    """Return whether content or pipeline changes require synchronization."""
    return (
        overwrite
        or checkpoint.index_status != "succeeded"
        or checkpoint.indexed_hash != checkpoint.content_hash
        or checkpoint.indexed_pipeline_fingerprint != pipeline_fingerprint
    )


def begin_indexing(
    checkpoint: IndexCheckpoint, *, now: datetime | None = None
) -> None:
    """Mark a checkpoint running before embedding or Search writes begin."""
    timestamp = now or _utc_now()
    checkpoint.index_status = "running"
    checkpoint.index_attempts += 1
    checkpoint.index_started_at = timestamp
    checkpoint.index_finished_at = None
    checkpoint.index_error = None
    checkpoint.updated_at = timestamp


def complete_indexing(
    checkpoint: IndexCheckpoint,
    *,
    pipeline_fingerprint: str,
    now: datetime | None = None,
) -> None:
    """Record a successful synchronization against current content and pipeline."""
    timestamp = now or _utc_now()
    checkpoint.index_status = "succeeded"
    checkpoint.indexed_hash = checkpoint.content_hash
    checkpoint.indexed_pipeline_fingerprint = pipeline_fingerprint
    checkpoint.index_finished_at = timestamp
    checkpoint.index_error = None
    checkpoint.updated_at = timestamp


def fail_indexing(
    checkpoint: IndexCheckpoint,
    error: Exception,
    *,
    now: datetime | None = None,
) -> None:
    """Record a retryable indexing failure without changing the indexed hashes."""
    timestamp = now or _utc_now()
    checkpoint.index_status = "failed"
    checkpoint.index_finished_at = timestamp
    checkpoint.index_error = str(error)[:4000]
    checkpoint.updated_at = timestamp


def reset_indexing(
    checkpoint: IndexCheckpoint, *, now: datetime | None = None
) -> None:
    """Invalidate an indexing checkpoint after explicit index recreation."""
    checkpoint.index_status = "pending"
    checkpoint.indexed_hash = None
    checkpoint.indexed_pipeline_fingerprint = None
    checkpoint.index_error = None
    checkpoint.updated_at = now or _utc_now()


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)
