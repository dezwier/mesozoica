"""Resumable acquisition, embedding, and indexing checkpoint transitions."""

from __future__ import annotations

import hashlib
import json
from datetime import datetime, timezone
from typing import Any, Protocol, Sequence


class AcquiredDocuments(Protocol):
    """Duck-typed acquisition payload hashes for a source checkpoint."""

    content_hash: str
    source_hash: str
    source_version: str | None


class AcquisitionCheckpoint(Protocol):
    """Mutable fields required by the acquisition state machine."""

    source_version: str | None
    source_hash: str | None
    content_hash: str | None
    embedded_hash: str | None
    embedded_pipeline_fingerprint: str | None
    indexed_hash: str | None
    indexed_pipeline_fingerprint: str | None
    acquisition_status: str
    embed_status: str
    index_status: str
    acquisition_attempts: int
    acquisition_error: str | None
    embed_error: str | None
    index_error: str | None
    acquisition_started_at: datetime | None
    acquisition_finished_at: datetime | None
    updated_at: datetime


class EmbeddingCheckpoint(Protocol):
    """Mutable fields required by the embedding state machine."""

    content_hash: str | None
    embedded_hash: str | None
    embedded_pipeline_fingerprint: str | None
    indexed_hash: str | None
    indexed_pipeline_fingerprint: str | None
    embed_status: str
    index_status: str
    embed_attempts: int
    embed_error: str | None
    index_error: str | None
    embed_started_at: datetime | None
    embed_finished_at: datetime | None
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
    """Record successful acquisition hashes; caller persists docs via repository."""
    changed = checkpoint.content_hash != result.content_hash
    checkpoint.content_hash = result.content_hash
    checkpoint.source_hash = result.source_hash
    checkpoint.source_version = result.source_version
    checkpoint.acquisition_status = "succeeded"
    checkpoint.acquisition_finished_at = now or _utc_now()
    checkpoint.acquisition_error = None
    if changed:
        _invalidate_embedding(checkpoint)
        _invalidate_indexing(checkpoint)
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


def embedding_needed(
    checkpoint: EmbeddingCheckpoint,
    *,
    pipeline_fingerprint: str,
    overwrite: bool = False,
) -> bool:
    """Return whether content or pipeline changes require re-embedding."""
    return (
        overwrite
        or checkpoint.embed_status != "succeeded"
        or checkpoint.embedded_hash != checkpoint.content_hash
        or checkpoint.embedded_pipeline_fingerprint != pipeline_fingerprint
    )


def begin_embedding(
    checkpoint: EmbeddingCheckpoint, *, now: datetime | None = None
) -> None:
    """Mark a checkpoint running before chunking or embedding begins."""
    timestamp = now or _utc_now()
    checkpoint.embed_status = "running"
    checkpoint.embed_attempts += 1
    checkpoint.embed_started_at = timestamp
    checkpoint.embed_finished_at = None
    checkpoint.embed_error = None
    checkpoint.updated_at = timestamp


def complete_embedding(
    checkpoint: EmbeddingCheckpoint,
    *,
    pipeline_fingerprint: str,
    previous_inventory_hash: str | None,
    new_inventory_hash: str,
    now: datetime | None = None,
) -> bool:
    """Record successful embedding; caller persists chunks via repository."""
    vectors_changed = previous_inventory_hash != new_inventory_hash
    timestamp = now or _utc_now()
    checkpoint.embed_status = "succeeded"
    checkpoint.embedded_hash = checkpoint.content_hash
    checkpoint.embedded_pipeline_fingerprint = pipeline_fingerprint
    checkpoint.embed_finished_at = timestamp
    checkpoint.embed_error = None
    if vectors_changed:
        _invalidate_indexing(checkpoint)
    checkpoint.updated_at = timestamp
    return vectors_changed


def fail_embedding(
    checkpoint: EmbeddingCheckpoint,
    error: Exception,
    *,
    now: datetime | None = None,
) -> None:
    """Record a retryable embedding failure without clearing prior vectors."""
    timestamp = now or _utc_now()
    checkpoint.embed_status = "failed"
    checkpoint.embed_finished_at = timestamp
    checkpoint.embed_error = str(error)[:4000]
    checkpoint.updated_at = timestamp


def reset_embedding(
    checkpoint: EmbeddingCheckpoint, *, now: datetime | None = None
) -> None:
    """Invalidate an embedding checkpoint (e.g. after forced overwrite)."""
    _invalidate_embedding(checkpoint)
    checkpoint.updated_at = now or _utc_now()


def indexing_needed(
    checkpoint: IndexCheckpoint,
    *,
    pipeline_fingerprint: str,
    overwrite: bool = False,
) -> bool:
    """Return whether content or pipeline changes require Azure synchronization."""
    return (
        overwrite
        or checkpoint.index_status != "succeeded"
        or checkpoint.indexed_hash != checkpoint.content_hash
        or checkpoint.indexed_pipeline_fingerprint != pipeline_fingerprint
    )


def begin_indexing(
    checkpoint: IndexCheckpoint, *, now: datetime | None = None
) -> None:
    """Mark a checkpoint running before Search writes begin."""
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
    """Record a successful Azure synchronization against current content and pipeline."""
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
    _invalidate_indexing(checkpoint)
    checkpoint.updated_at = now or _utc_now()


def embedding_inventory_hash(chunks: Sequence[Any]) -> str:
    """Stable hash of chunk vector identities for change detection."""
    inventory = sorted(
        (
            str(_chunk_field(chunk, "id") or ""),
            str(_chunk_field(chunk, "embedding_hash") or ""),
            str(_chunk_field(chunk, "pipeline_fingerprint") or ""),
        )
        for chunk in chunks
    )
    payload = json.dumps(inventory, ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def _invalidate_embedding(checkpoint: AcquisitionCheckpoint | EmbeddingCheckpoint) -> None:
    checkpoint.embed_status = "pending"
    checkpoint.embedded_hash = None
    checkpoint.embedded_pipeline_fingerprint = None
    checkpoint.embed_error = None


def _invalidate_indexing(
    checkpoint: AcquisitionCheckpoint | EmbeddingCheckpoint | IndexCheckpoint,
) -> None:
    checkpoint.index_status = "pending"
    checkpoint.indexed_hash = None
    checkpoint.indexed_pipeline_fingerprint = None
    checkpoint.index_error = None


def _chunk_field(chunk: Any, name: str) -> Any:
    if hasattr(chunk, name):
        return getattr(chunk, name)
    if isinstance(chunk, dict):
        return chunk.get(name)
    return None


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)
