"""Checkpointed multi-snapshot embedding and Azure ingest."""

from __future__ import annotations

import logging
from collections.abc import Callable, Sequence
from typing import Any, TypeVar

from mesozoica_ai.common.batch import (
    DEFAULT_NAMESPACE,
    DEFAULT_SUBJECT_KIND,
    JobSummary,
    snapshot_scope,
)
from mesozoica_ai.common.checkpoints import (
    begin_embedding,
    begin_indexing,
    complete_embedding,
    complete_indexing,
    embedding_needed,
    fail_embedding,
    fail_indexing,
    indexing_needed,
    reset_indexing,
)
from mesozoica_ai.common.config import AiConfig
from mesozoica_ai.common.resume import UnitOfWork, run_resumable_item
from mesozoica_ai.common.store import SessionUnitOfWork
from mesozoica_ai.index.api import (
    ensure_index,
    pipeline_fingerprint,
    prepare_embeddings,
    recreate_index as recreate_search_index,
    sync_embedded_chunks,
)
from mesozoica_ai.index.runtime import build_store

CheckpointT = TypeVar("CheckpointT")
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


def embed_snapshots(
    *,
    config: AiConfig,
    snapshots: Sequence[CheckpointT],
    work_unit: UnitOfWork,
    reload: Callable[[CheckpointT], CheckpointT],
    documents_for: Callable[[CheckpointT], Any] | None = None,
    embedded_for: Callable[[CheckpointT], Any] | None = None,
    label_for: Callable[[CheckpointT], str] | None = None,
    overwrite: bool = False,
    dry_run: bool = False,
) -> JobSummary:
    """Chunk and embed checkpointed document snapshots into SQL."""
    resolve_documents = documents_for or (lambda row: row.documents)
    resolve_embedded = embedded_for or (lambda row: row.embedded_chunks or [])
    if dry_run:
        summary = JobSummary(candidates=len(snapshots))
        summary.skipped = len(snapshots)
        return summary

    fingerprint = pipeline_fingerprint(config=config)
    pending: list[CheckpointT] = []
    already_embedded = 0
    for snapshot in snapshots:
        if embedding_needed(
            snapshot, pipeline_fingerprint=fingerprint, overwrite=overwrite
        ):
            pending.append(snapshot)
        else:
            already_embedded += 1

    logger.info(
        "dinosaur_knowledge embed: %s acquired row(s); %s pending, %s already embedded",
        len(snapshots),
        len(pending),
        already_embedded,
    )
    summary = JobSummary(candidates=len(snapshots))
    summary.skipped = already_embedded
    if not pending:
        return summary

    for snapshot in pending:
        prepare_result: dict[str, Any] = {}
        label = (
            label_for(snapshot)
            if label_for
            else f"{snapshot.subject_name}/{snapshot.source}"
        )

        def work(row: CheckpointT, *, _result=prepare_result) -> None:
            _result["result"] = prepare_embeddings(
                resolve_documents(row),
                config=config,
                existing=resolve_embedded(row),
            )

        logger.info("%s: embedding", label)
        outcome = run_resumable_item(
            work_unit,
            snapshot,
            should_run=lambda row: True,
            begin=begin_embedding,
            work=work,
            complete=lambda row, _result=prepare_result: complete_embedding(
                row,
                embedded_chunks=_result["result"].chunks,
                pipeline_fingerprint=_result["result"].pipeline_fingerprint,
            ),
            fail=fail_embedding,
            reload=reload,
            label=label,
        )
        if outcome == "succeeded":
            result = prepare_result.get("result")
            if result is not None:
                logger.info(
                    "%s: done embed=%s reuse=%s chunks=%s",
                    label,
                    getattr(result, "embedded_count", "?"),
                    getattr(result, "reused_count", "?"),
                    getattr(result, "chunk_count", "?"),
                )
            else:
                logger.info("%s: done", label)
        elif outcome == "failed":
            logger.error("%s: failed", label)
        elif outcome == "skipped":
            summary.skipped += 1
            continue
        summary.record(outcome)
    return summary


def ingest_snapshots(
    *,
    config: AiConfig,
    snapshots: Sequence[CheckpointT],
    work_unit: UnitOfWork,
    reload: Callable[[CheckpointT], CheckpointT],
    scope_for: Callable[[CheckpointT], dict[str, Any]] | None = None,
    embedded_for: Callable[[CheckpointT], Any] | None = None,
    label_for: Callable[[CheckpointT], str] | None = None,
    overwrite: bool = False,
    dry_run: bool = False,
    prepare_index: bool = True,
    recreate_index: bool = False,
    snapshots_to_reset: Sequence[CheckpointT] | None = None,
    namespace: str = DEFAULT_NAMESPACE,
    subject_kind: str = DEFAULT_SUBJECT_KIND,
) -> JobSummary:
    """Upload SQL-cached embeddings into Azure Search."""
    resolve_scope = scope_for or (
        lambda row: snapshot_scope(row, namespace=namespace, subject_kind=subject_kind)
    )
    resolve_embedded = embedded_for or (lambda row: row.embedded_chunks or [])
    if dry_run:
        summary = JobSummary(candidates=len(snapshots))
        summary.skipped = len(snapshots)
        return summary
    if recreate_index:
        logger.warning(
            "Recreating Azure index and resetting index checkpoints",
        )
        recreate_search_index(config=config)
        for snapshot in snapshots_to_reset or ():
            reset_indexing(snapshot)
            work_unit.save(snapshot)
        work_unit.commit()
        snapshots = [reload(snapshot) for snapshot in snapshots]
        prepare_index = False
    if prepare_index:
        ensure_index(config=config)
        index_name = getattr(config, "search_index", None) or "?"
        logger.info("Azure index ready (%s)", index_name)

    fingerprint = pipeline_fingerprint(config=config)
    store = build_store(config, write_enabled=False)
    pending: list[CheckpointT] = []
    already_indexed = 0
    drift_resets = 0
    for snapshot in snapshots:
        label = (
            label_for(snapshot)
            if label_for
            else f"{snapshot.subject_name}/{snapshot.source}"
        )
        if getattr(snapshot, "embed_status", None) != "succeeded":
            logger.info("%s: skip ingest (embed_status=%s)", label, getattr(snapshot, "embed_status", None))
            continue
        embedded = list(resolve_embedded(snapshot) or [])
        if not embedded:
            logger.info("%s: skip ingest (no embedded_chunks)", label)
            continue
        if indexing_needed(
            snapshot, pipeline_fingerprint=fingerprint, overwrite=overwrite
        ):
            pending.append(snapshot)
            continue
        chunk_ids = {
            str(chunk.get("id") or "")
            for chunk in embedded
            if chunk.get("id")
        }
        try:
            azure_ids = store.existing_ids(sorted(chunk_ids))
        except Exception as exc:
            logger.warning("%s: Azure verify failed (%s); re-syncing", label, exc)
            reset_indexing(snapshot)
            work_unit.save(snapshot)
            pending.append(snapshot)
            drift_resets += 1
            continue
        if chunk_ids == azure_ids:
            already_indexed += 1
            continue
        logger.info(
            "%s: Azure drift (sql_chunks=%s azure_keys=%s); re-syncing",
            label,
            len(chunk_ids),
            len(azure_ids),
        )
        reset_indexing(snapshot)
        work_unit.save(snapshot)
        pending.append(snapshot)
        drift_resets += 1
    if drift_resets:
        work_unit.commit()

    eligible = [
        snapshot
        for snapshot in snapshots
        if getattr(snapshot, "embed_status", None) == "succeeded"
        and list(resolve_embedded(snapshot) or [])
    ]
    logger.info(
        "dinosaur_knowledge ingest: %s embedded row(s); %s pending, %s already indexed%s",
        len(eligible),
        len(pending),
        already_indexed,
        f", {drift_resets} Azure drift" if drift_resets else "",
    )
    summary = JobSummary(candidates=len(eligible))
    summary.skipped = already_indexed + (len(snapshots) - len(eligible))
    if not pending:
        return summary

    for snapshot in pending:
        sync_result: dict[str, Any] = {}
        label = (
            label_for(snapshot)
            if label_for
            else f"{snapshot.subject_name}/{snapshot.source}"
        )

        def work(row: CheckpointT, *, _result=sync_result) -> None:
            _result["result"] = sync_embedded_chunks(
                resolve_embedded(row),
                scope=resolve_scope(row),
                config=config,
            )

        logger.info("%s: ingesting", label)
        outcome = run_resumable_item(
            work_unit,
            snapshot,
            should_run=lambda row: True,
            begin=begin_indexing,
            work=work,
            complete=lambda row, _result=sync_result: complete_indexing(
                row, pipeline_fingerprint=_result["result"].pipeline_fingerprint
            ),
            fail=fail_indexing,
            reload=reload,
            label=label,
        )
        if outcome == "succeeded":
            result = sync_result.get("result")
            if result is not None:
                logger.info(
                    "%s: done upsert=%s skip=%s meta=%s delete=%s",
                    label,
                    getattr(result, "embedded_count", "?"),
                    getattr(result, "skipped_count", "?"),
                    getattr(result, "metadata_updated_count", "?"),
                    getattr(result, "deleted_count", "?"),
                )
            else:
                logger.info("%s: done", label)
        elif outcome == "failed":
            logger.error("%s: failed", label)
        elif outcome == "skipped":
            summary.skipped += 1
            continue
        summary.record(outcome)
    return summary


def index_snapshots(
    *,
    config: AiConfig,
    snapshots: Sequence[CheckpointT],
    work_unit: UnitOfWork,
    reload: Callable[[CheckpointT], CheckpointT],
    scope_for: Callable[[CheckpointT], dict[str, Any]] | None = None,
    documents_for: Callable[[CheckpointT], Any] | None = None,
    label_for: Callable[[CheckpointT], str] | None = None,
    overwrite: bool = False,
    dry_run: bool = False,
    prepare_index: bool = True,
    recreate_index: bool = False,
    snapshots_to_reset: Sequence[CheckpointT] | None = None,
    namespace: str = DEFAULT_NAMESPACE,
    subject_kind: str = DEFAULT_SUBJECT_KIND,
) -> JobSummary:
    """Embed then ingest checkpointed snapshots (compat convenience)."""
    embed_summary = embed_snapshots(
        config=config,
        snapshots=snapshots,
        work_unit=work_unit,
        reload=reload,
        documents_for=documents_for,
        label_for=label_for,
        overwrite=overwrite,
        dry_run=dry_run,
    )
    if dry_run:
        return embed_summary
    # Reload after embed so ingest sees persisted vectors / statuses.
    snapshots = [reload(snapshot) for snapshot in snapshots]
    ingest_summary = ingest_snapshots(
        config=config,
        snapshots=snapshots,
        work_unit=work_unit,
        reload=reload,
        scope_for=scope_for,
        label_for=label_for,
        overwrite=overwrite,
        dry_run=False,
        prepare_index=prepare_index,
        recreate_index=recreate_index,
        snapshots_to_reset=snapshots_to_reset,
        namespace=namespace,
        subject_kind=subject_kind,
    )
    return JobSummary(
        candidates=max(embed_summary.candidates, ingest_summary.candidates),
        succeeded=ingest_summary.succeeded,
        skipped=ingest_summary.skipped,
        failed=embed_summary.failed + ingest_summary.failed,
    )


def embed_knowledge(
    *,
    session: Any,
    model: type[Any],
    config: AiConfig | None = None,
    names: list[str] | None = None,
    sources: list[str] | None = None,
    max_items: int | None = None,
    overwrite: bool = False,
    dry_run: bool = False,
    subject_kind: str = DEFAULT_SUBJECT_KIND,
) -> JobSummary:
    """Chunk/embed acquired checkpoint rows into ``embedded_chunks`` SQL."""
    active = config or AiConfig()

    def reload(row: Any) -> Any:
        loaded = session.get(model, row.id)
        if loaded is None:  # pragma: no cover - defensive
            raise RuntimeError(f"Missing knowledge snapshot after failure: {row.id}")
        return loaded

    return embed_snapshots(
        config=active,
        snapshots=_list_indexable(
            session,
            model,
            names=names,
            sources=sources,
            max_items=max_items,
            subject_kind=subject_kind,
        ),
        work_unit=SessionUnitOfWork(session),
        reload=reload,
        overwrite=overwrite,
        dry_run=dry_run,
    )


def ingest_knowledge(
    *,
    session: Any,
    model: type[Any],
    config: AiConfig | None = None,
    names: list[str] | None = None,
    sources: list[str] | None = None,
    max_items: int | None = None,
    overwrite: bool = False,
    dry_run: bool = False,
    recreate_index: bool = False,
    subject_kind: str = DEFAULT_SUBJECT_KIND,
) -> JobSummary:
    """Ingest SQL-cached embeddings from ``model`` into Azure Search."""
    active = config or AiConfig()
    if recreate_index:
        require_full_recreate_scope(names=names, sources=sources, max_items=max_items)

    def reload(row: Any) -> Any:
        loaded = session.get(model, row.id)
        if loaded is None:  # pragma: no cover - defensive
            raise RuntimeError(f"Missing knowledge snapshot after failure: {row.id}")
        return loaded

    return ingest_snapshots(
        config=active,
        snapshots=_list_indexable(
            session,
            model,
            names=names,
            sources=sources,
            max_items=max_items,
            subject_kind=subject_kind,
        ),
        work_unit=SessionUnitOfWork(session),
        reload=reload,
        overwrite=overwrite,
        dry_run=dry_run,
        recreate_index=recreate_index,
        snapshots_to_reset=(
            _list_succeeded(session, model, subject_kind=subject_kind)
            if recreate_index
            else None
        ),
        subject_kind=subject_kind,
    )


def index_knowledge(
    *,
    session: Any,
    model: type[Any],
    config: AiConfig | None = None,
    names: list[str] | None = None,
    sources: list[str] | None = None,
    max_items: int | None = None,
    overwrite: bool = False,
    dry_run: bool = False,
    recreate_index: bool = False,
    subject_kind: str = DEFAULT_SUBJECT_KIND,
) -> JobSummary:
    """Embed then ingest acquired checkpoint rows (compat convenience)."""
    active = config or AiConfig()
    if recreate_index:
        require_full_recreate_scope(names=names, sources=sources, max_items=max_items)

    def reload(row: Any) -> Any:
        loaded = session.get(model, row.id)
        if loaded is None:  # pragma: no cover - defensive
            raise RuntimeError(f"Missing knowledge snapshot after failure: {row.id}")
        return loaded

    snapshots = _list_indexable(
        session,
        model,
        names=names,
        sources=sources,
        max_items=max_items,
        subject_kind=subject_kind,
    )
    return index_snapshots(
        config=active,
        snapshots=snapshots,
        work_unit=SessionUnitOfWork(session),
        reload=reload,
        overwrite=overwrite,
        dry_run=dry_run,
        recreate_index=recreate_index,
        snapshots_to_reset=(
            _list_succeeded(session, model, subject_kind=subject_kind)
            if recreate_index
            else None
        ),
        subject_kind=subject_kind,
    )


def list_knowledge_rows(
    session: Any,
    model: type[Any],
    *,
    names: list[str] | None = None,
    succeeded_only: bool = False,
    subject_kind: str = DEFAULT_SUBJECT_KIND,
) -> list[Any]:
    """List checkpoint rows for status or evaluation."""
    from sqlmodel import col, select

    statement = (
        select(model)
        .where(model.subject_kind == subject_kind)
        .order_by(col(model.subject_name), col(model.source))
    )
    if succeeded_only:
        statement = statement.where(model.acquisition_status == "succeeded")
    rows = list(session.exec(statement).all())
    return _filter_names(rows, names)


def _list_indexable(
    session: Any,
    model: type[Any],
    *,
    names: list[str] | None,
    sources: list[str] | None,
    max_items: int | None,
    subject_kind: str,
) -> list[Any]:
    from sqlmodel import col, select

    selected = _normalize_sources(sources)
    statement = (
        select(model)
        .where(
            model.subject_kind == subject_kind,
            model.acquisition_status == "succeeded",
            col(model.source).in_(selected),
        )
        .order_by(col(model.subject_name), col(model.source))
    )
    return _filter_names(list(session.exec(statement).all()), names, max_items=max_items)


def _list_succeeded(
    session: Any, model: type[Any], *, subject_kind: str
) -> list[Any]:
    return list_knowledge_rows(
        session, model, succeeded_only=True, subject_kind=subject_kind
    )


def _normalize_sources(sources: Sequence[str] | None) -> list[str]:
    values = SUPPORTED_SOURCES if not sources else sources
    normalized = [str(value).strip().casefold() for value in values if str(value).strip()]
    unknown = sorted(set(normalized) - set(SUPPORTED_SOURCES))
    if unknown:
        raise ValueError(f"Unsupported knowledge sources: {', '.join(unknown)}")
    return list(dict.fromkeys(normalized))


def _filter_names(
    rows: list[Any],
    names: list[str] | None,
    *,
    max_items: int | None = None,
) -> list[Any]:
    if names:
        wanted = {name.strip().casefold() for name in names if name.strip()}
        rows = [row for row in rows if row.subject_name.casefold() in wanted]
    if max_items is not None:
        rows = rows[:max_items]
    return rows
