"""Checkpointed multi-snapshot embedding and Azure ingest."""

from __future__ import annotations

import logging
from collections.abc import Sequence
from typing import Any

from mesozoica_ai.common.batch import (
    DEFAULT_SUBJECT_KIND,
    JobSummary,
    snapshot_scope,
)
from mesozoica_ai.common.checkpoints import (
    begin_embedding,
    begin_indexing,
    complete_embedding,
    complete_indexing,
    embedding_inventory_hash,
    embedding_needed,
    fail_embedding,
    fail_indexing,
    indexing_needed,
    reset_indexing,
)
from mesozoica_ai.common.config import AiConfig
from mesozoica_ai.common.errors import EmbeddingProviderError, BatchWriteError
from mesozoica_ai.common.knowledge_repo import KnowledgeRepository
from mesozoica_ai.common.resume import UnitOfWork, run_resumable_item
from mesozoica_ai.common.store import SessionUnitOfWork
from mesozoica_ai.index.api import (
    ensure_index,
    pipeline_fingerprint,
    prepare_embeddings,
    recreate_index as recreate_search_index,
    sync_embedded_chunks,
)
from mesozoica_ai.index.runtime import build_embedder, build_store

SUPPORTED_SOURCES = ("wikipedia", "openalex")
logger = logging.getLogger(__name__)


def require_full_recreate_scope(
    *,
    names: Sequence[str] | None,
    sources: Sequence[str] | None,
    max_items: int | None,
) -> list[str]:
    """Reject partial recreate requests that would leave stale index scopes."""
    values = SUPPORTED_SOURCES if sources is None else sources
    selected = list(
        dict.fromkeys(
            str(value).strip().casefold() for value in values if str(value).strip()
        )
    )
    if names or max_items is not None or set(selected) != set(SUPPORTED_SOURCES):
        raise ValueError(
            "--recreate-index must run unscoped: omit --dinos/--max-items and include both sources"
        )
    return selected


class _RepoUnitOfWork:
    def __init__(self, repo: KnowledgeRepository) -> None:
        self._repo = repo

    def save(self, item: object) -> None:
        self._repo.save_source(item)

    def commit(self) -> None:
        self._repo.commit()

    def rollback(self) -> None:
        session = getattr(self._repo, "session", None)
        if session is not None:
            session.rollback()


def embed_knowledge(
    *,
    repo: KnowledgeRepository,
    config: AiConfig | None = None,
    names: list[str] | None = None,
    sources: list[str] | None = None,
    max_items: int | None = None,
    overwrite: bool = False,
    dry_run: bool = False,
    subject_kind: str = DEFAULT_SUBJECT_KIND,
) -> JobSummary:
    """Chunk/embed acquired sources into ``dinosaur_knowledge_chunk`` rows."""
    active = config or AiConfig()
    selected = _normalize_sources(sources)
    snapshots = repo.list_sources(
        subject_kind=subject_kind,
        names=names,
        sources=selected,
        acquisition_succeeded_only=True,
        max_items=max_items,
    )
    if dry_run:
        summary = JobSummary(candidates=len(snapshots))
        summary.skipped = len(snapshots)
        return summary

    fingerprint = pipeline_fingerprint(config=active)
    pending = []
    already_embedded = 0
    for snapshot in snapshots:
        if embedding_needed(
            snapshot, pipeline_fingerprint=fingerprint, overwrite=overwrite
        ):
            pending.append(snapshot)
        else:
            already_embedded += 1

    pending_total = len(pending)
    pending_dinos = len({str(row.subject_id) for row in pending})
    acquired_dinos = len({str(row.subject_id) for row in snapshots})
    logger.info(
        "Embed → SQL: %s source-row(s) to embed (%s dino(s)); "
        "%s source-row(s) already embedded; "
        "%s acquired source-row(s) / %s dino(s) | %s @ %s dims",
        pending_total,
        pending_dinos,
        already_embedded,
        len(snapshots),
        acquired_dinos,
        active.embedding_deployment,
        active.embedding_dimensions,
    )
    summary = JobSummary(candidates=len(snapshots))
    summary.skipped = already_embedded
    work_unit: UnitOfWork = _RepoUnitOfWork(repo)
    # One Azure OpenAI client for the whole run. Recreating per dinosaur races
    # Foundry routing and surfaces intermittent unknown_model 400s.
    embedder = build_embedder(active)
    try:
        embedder.embed_query("mesozoica embedding probe")
    except Exception as exc:
        raise EmbeddingProviderError(
            f"Embedding probe failed for deployment "
            f"{active.embedding_deployment!r}: {exc}"
        ) from exc

    for embed_i, snapshot in enumerate(pending, start=1):
        label = f"{snapshot.subject_name}/{snapshot.source}"
        prepare_result: dict[str, Any] = {}
        fail_info: dict[str, BaseException] = {}

        def work(row: Any, *, _result=prepare_result) -> None:
            existing = repo.list_chunks(row)
            prepared = prepare_embeddings(
                repo.list_documents(row),
                config=active,
                existing=existing,
                embedder=embedder,
            )
            _result["prepared"] = prepared
            _result["previous_inventory"] = embedding_inventory_hash(existing)
            _result["new_inventory"] = embedding_inventory_hash(prepared.chunks)
            repo.replace_chunks(row, prepared.chunks)

        def complete(row: Any, *, _result=prepare_result) -> None:
            prepared = _result["prepared"]
            complete_embedding(
                row,
                pipeline_fingerprint=prepared.pipeline_fingerprint,
                previous_inventory_hash=_result["previous_inventory"],
                new_inventory_hash=_result["new_inventory"],
            )

        def fail(row: Any, exc: BaseException, *, _info=fail_info) -> None:
            _info["exc"] = exc
            fail_embedding(row, exc)

        def reload(row: Any) -> Any:
            loaded = repo.get_source(
                subject_kind=row.subject_kind,
                subject_id=row.subject_id,
                source=row.source,
            )
            if loaded is None:
                raise RuntimeError(f"Missing knowledge source after failure: {row.id}")
            return loaded

        try:
            outcome = run_resumable_item(
                work_unit,
                snapshot,
                should_run=lambda row: True,
                begin=begin_embedding,
                work=work,
                complete=complete,
                fail=fail,
                reload=reload,
                label=label,
                reraise=lambda exc: isinstance(exc, EmbeddingProviderError),
            )
        except EmbeddingProviderError as exc:
            summary.failed += 1
            logger.error(
                "embed %s/%s %s | SQL failed (stopping): %s",
                embed_i,
                pending_total,
                label,
                exc,
            )
            return summary
        if outcome == "succeeded":
            prepared = prepare_result.get("prepared")
            if prepared is not None:
                logger.info(
                    "embed %s/%s %s | SQL ok +%s reuse=%s total=%s",
                    embed_i,
                    pending_total,
                    label,
                    prepared.embedded_count,
                    prepared.reused_count,
                    prepared.chunk_count,
                )
            else:
                logger.info(
                    "embed %s/%s %s | SQL ok",
                    embed_i,
                    pending_total,
                    label,
                )
        elif outcome == "failed":
            reason = fail_info.get("exc") or "unknown error"
            logger.error(
                "embed %s/%s %s | SQL failed: %s",
                embed_i,
                pending_total,
                label,
                reason,
            )
        elif outcome == "skipped":
            summary.skipped += 1
            continue
        summary.record(outcome)
    return summary


def ingest_knowledge(
    *,
    repo: KnowledgeRepository,
    config: AiConfig | None = None,
    names: list[str] | None = None,
    sources: list[str] | None = None,
    max_items: int | None = None,
    overwrite: bool = False,
    dry_run: bool = False,
    recreate_index: bool = False,
    subject_kind: str = DEFAULT_SUBJECT_KIND,
) -> JobSummary:
    """Ingest SQL chunks into Azure Search."""
    active = config or AiConfig()
    if recreate_index:
        require_full_recreate_scope(names=names, sources=sources, max_items=max_items)

    selected = _normalize_sources(sources)
    snapshots = repo.list_sources(
        subject_kind=subject_kind,
        names=names,
        sources=selected,
        acquisition_succeeded_only=True,
        max_items=max_items,
    )
    if dry_run:
        summary = JobSummary(candidates=len(snapshots))
        summary.skipped = len(snapshots)
        return summary

    work_unit: UnitOfWork = _RepoUnitOfWork(repo)
    if recreate_index:
        logger.warning("Recreating Azure index and resetting index checkpoints")
        recreate_search_index(config=active)
        for snapshot in repo.list_sources(
            subject_kind=subject_kind, acquisition_succeeded_only=True
        ):
            reset_indexing(snapshot)
            repo.save_source(snapshot)
        repo.commit()
        snapshots = [
            repo.get_source(
                subject_kind=row.subject_kind,
                subject_id=row.subject_id,
                source=row.source,
            )
            or row
            for row in snapshots
        ]
    else:
        ensure_index(config=active)
        logger.debug(
            "Azure index ready (%s)", getattr(active, "search_index", None) or "?"
        )

    fingerprint = pipeline_fingerprint(config=active)
    store = build_store(active, write_enabled=False)
    pending = []
    already_indexed = 0
    drift_resets = 0
    skip_by_status: dict[str, int] = {}
    skip_no_chunks = 0
    queue_fresh = 0

    def _skip_status_summary() -> str:
        parts = [f"{status}={count}" for status, count in sorted(skip_by_status.items())]
        if skip_no_chunks:
            parts.append(f"no_chunks={skip_no_chunks}")
        return ", ".join(parts) if parts else "0"

    # Sync-check is quiet on purpose; one prep line is logged after it finishes.
    for snapshot in snapshots:
        label = f"{snapshot.subject_name}/{snapshot.source}"
        if snapshot.embed_status != "succeeded":
            skip_by_status[snapshot.embed_status] = (
                skip_by_status.get(snapshot.embed_status, 0) + 1
            )
            logger.debug("%s: not ready (embed_status=%s)", label, snapshot.embed_status)
            continue
        chunks = repo.list_chunks(snapshot)
        if not chunks:
            skip_no_chunks += 1
            logger.debug("%s: not ready (no chunks)", label)
            continue
        if indexing_needed(
            snapshot, pipeline_fingerprint=fingerprint, overwrite=overwrite
        ):
            pending.append(snapshot)
            queue_fresh += 1
            continue
        chunk_ids = {chunk.id for chunk in chunks}
        try:
            # Scoped search (one query per source) instead of N get_document calls.
            azure_ids = set(store.get_chunk_states(snapshot_scope(snapshot)))
        except Exception as exc:
            logger.debug("%s: Azure verify failed (%s); queue re-sync", label, exc)
            reset_indexing(snapshot)
            repo.save_source(snapshot)
            pending.append(snapshot)
            drift_resets += 1
            continue
        if chunk_ids == azure_ids:
            already_indexed += 1
            continue
        logger.debug(
            "%s: drift sql=%s azure=%s",
            label,
            len(chunk_ids),
            len(azure_ids),
        )
        reset_indexing(snapshot)
        repo.save_source(snapshot)
        pending.append(snapshot)
        drift_resets += 1
    if drift_resets:
        repo.commit()

    eligible = [
        snapshot
        for snapshot in snapshots
        if snapshot.embed_status == "succeeded" and repo.list_chunks(snapshot)
    ]
    upsert_total = len(pending)
    upsert_dinos = len({str(row.subject_id) for row in pending})
    acquired_dinos = len({str(row.subject_id) for row in snapshots})
    logger.info(
        "Ingest → Azure: %s source-row(s) to upsert (%s dino(s)); "
        "%s source-row(s) already in sync; "
        "%s drift re-queued; %s fresh; "
        "not_ready=%s; "
        "%s acquired source-row(s) / %s dino(s) | index=%s",
        upsert_total,
        upsert_dinos,
        already_indexed,
        drift_resets,
        queue_fresh,
        _skip_status_summary(),
        len(snapshots),
        acquired_dinos,
        getattr(active, "search_index", None) or "?",
    )
    summary = JobSummary(candidates=len(eligible))
    summary.skipped = already_indexed + (len(snapshots) - len(eligible))

    for upsert_i, snapshot in enumerate(pending, start=1):
        label = f"{snapshot.subject_name}/{snapshot.source}"
        sync_result: dict[str, Any] = {}
        fail_info: dict[str, BaseException] = {}

        def work(row: Any, *, _result=sync_result) -> None:
            _result["result"] = sync_embedded_chunks(
                repo.list_chunks(row),
                scope=snapshot_scope(row),
                config=active,
            )

        def fail(row: Any, exc: BaseException, *, _info=fail_info) -> None:
            _info["exc"] = exc
            fail_indexing(row, exc)

        def reload(row: Any) -> Any:
            loaded = repo.get_source(
                subject_kind=row.subject_kind,
                subject_id=row.subject_id,
                source=row.source,
            )
            if loaded is None:
                raise RuntimeError(f"Missing knowledge source after failure: {row.id}")
            return loaded

        try:
            outcome = run_resumable_item(
                work_unit,
                snapshot,
                should_run=lambda row: True,
                begin=begin_indexing,
                work=work,
                complete=lambda row, _result=sync_result: complete_indexing(
                    row, pipeline_fingerprint=_result["result"].pipeline_fingerprint
                ),
                fail=fail,
                reload=reload,
                label=label,
                reraise=_is_index_capacity_error,
            )
        except BatchWriteError as exc:
            summary.failed += 1
            logger.error(
                "upsert %s/%s %s | Azure failed (stopping): %s",
                upsert_i,
                upsert_total,
                label,
                exc,
            )
            return summary
        if outcome == "succeeded":
            result = sync_result.get("result")
            if result is not None:
                logger.info(
                    "upsert %s/%s %s | Azure ok +%s skip=%s meta=%s del=%s",
                    upsert_i,
                    upsert_total,
                    label,
                    result.embedded_count,
                    result.skipped_count,
                    result.metadata_updated_count,
                    result.deleted_count,
                )
            else:
                logger.info(
                    "upsert %s/%s %s | Azure ok",
                    upsert_i,
                    upsert_total,
                    label,
                )
        elif outcome == "failed":
            reason = fail_info.get("exc") or "unknown error"
            logger.error(
                "upsert %s/%s %s | Azure failed: %s",
                upsert_i,
                upsert_total,
                label,
                reason,
            )
        elif outcome == "skipped":
            summary.skipped += 1
            continue
        summary.record(outcome)
    return summary


def index_knowledge(
    *,
    repo: KnowledgeRepository,
    config: AiConfig | None = None,
    names: list[str] | None = None,
    sources: list[str] | None = None,
    max_items: int | None = None,
    overwrite: bool = False,
    dry_run: bool = False,
    recreate_index: bool = False,
    subject_kind: str = DEFAULT_SUBJECT_KIND,
) -> JobSummary:
    """Embed then ingest (compat convenience)."""
    if recreate_index:
        require_full_recreate_scope(names=names, sources=sources, max_items=max_items)
    embed_summary = embed_knowledge(
        repo=repo,
        config=config,
        names=names,
        sources=sources,
        max_items=max_items,
        overwrite=overwrite,
        dry_run=dry_run,
        subject_kind=subject_kind,
    )
    if dry_run:
        return embed_summary
    ingest_summary = ingest_knowledge(
        repo=repo,
        config=config,
        names=names,
        sources=sources,
        max_items=max_items,
        overwrite=overwrite,
        dry_run=False,
        recreate_index=recreate_index,
        subject_kind=subject_kind,
    )
    return JobSummary(
        candidates=max(embed_summary.candidates, ingest_summary.candidates),
        succeeded=ingest_summary.succeeded,
        skipped=ingest_summary.skipped,
        failed=embed_summary.failed + ingest_summary.failed,
    )


def list_knowledge_rows(
    repo: KnowledgeRepository,
    *,
    names: list[str] | None = None,
    succeeded_only: bool = False,
    subject_kind: str = DEFAULT_SUBJECT_KIND,
) -> list[Any]:
    """List source rows for status or evaluation."""
    return repo.list_sources(
        subject_kind=subject_kind,
        names=names,
        acquisition_succeeded_only=succeeded_only,
    )


def _normalize_sources(sources: Sequence[str] | None) -> list[str]:
    values = SUPPORTED_SOURCES if not sources else sources
    normalized = [str(value).strip().casefold() for value in values if str(value).strip()]
    unknown = sorted(set(normalized) - set(SUPPORTED_SOURCES))
    if unknown:
        raise ValueError(f"Unsupported knowledge sources: {', '.join(unknown)}")
    return normalized


def _is_index_capacity_error(exc: BaseException) -> bool:
    if not isinstance(exc, BatchWriteError):
        return False
    text = " ".join(
        part for part in (exc.reason, str(exc)) if part
    ).casefold()
    return "vector quota" in text or "storage quota" in text or "quota has been exceeded" in text
