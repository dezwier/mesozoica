"""Checkpointed multi-snapshot Azure indexing."""

from __future__ import annotations

from collections.abc import Callable, Sequence
from typing import Any, TypeVar

from mesozoica_ai.common.batch import (
    DEFAULT_NAMESPACE,
    DEFAULT_SUBJECT_KIND,
    JobSummary,
    snapshot_scope,
)
from mesozoica_ai.common.checkpoints import (
    begin_indexing,
    complete_indexing,
    fail_indexing,
    indexing_needed,
    reset_indexing,
)
from mesozoica_ai.common.config import AiConfig
from mesozoica_ai.common.resume import UnitOfWork, run_resumable_item
from mesozoica_ai.index.api import (
    ensure_index,
    pipeline_fingerprint,
    recreate_index as recreate_search_index,
    sync_documents,
)

CheckpointT = TypeVar("CheckpointT")


def require_full_recreate_scope(
    *,
    names: Sequence[str] | None,
    sources: Sequence[str] | None,
    max_items: int | None,
) -> list[str]:
    """Reject partial recreate requests that would leave stale index scopes."""
    values = ("wikipedia", "openalex") if sources is None else sources
    selected = list(
        dict.fromkeys(
            str(value).strip().casefold() for value in values if str(value).strip()
        )
    )
    if names or max_items is not None or set(selected) != {"wikipedia", "openalex"}:
        raise ValueError(
            "--recreate-index must run unscoped: omit --dinos/--max-items and include both sources"
        )
    return selected


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
    """Synchronize checkpointed document snapshots into Azure Search."""
    resolve_scope = scope_for or (
        lambda row: snapshot_scope(row, namespace=namespace, subject_kind=subject_kind)
    )
    resolve_documents = documents_for or (lambda row: row.documents)
    if dry_run:
        summary = JobSummary(candidates=len(snapshots))
        summary.skipped = len(snapshots)
        return summary
    if recreate_index:
        recreate_search_index(config=config)
        for snapshot in snapshots_to_reset or ():
            reset_indexing(snapshot)
            work_unit.save(snapshot)
        work_unit.commit()
        snapshots = [reload(snapshot) for snapshot in snapshots]
        prepare_index = False
    summary = JobSummary(candidates=len(snapshots))
    if prepare_index:
        ensure_index(config=config)
    fingerprint = pipeline_fingerprint(config=config)
    for snapshot in snapshots:
        sync_result: dict[str, Any] = {}

        def work(row: CheckpointT, *, _result=sync_result) -> None:
            _result["result"] = sync_documents(
                resolve_documents(row),
                scope=resolve_scope(row),
                config=config,
            )

        outcome = run_resumable_item(
            work_unit,
            snapshot,
            should_run=lambda row: indexing_needed(
                row, pipeline_fingerprint=fingerprint, overwrite=overwrite
            ),
            begin=begin_indexing,
            work=work,
            complete=lambda row, _result=sync_result: complete_indexing(
                row, pipeline_fingerprint=_result["result"].pipeline_fingerprint
            ),
            fail=fail_indexing,
            reload=reload,
            label=(
                label_for(snapshot)
                if label_for
                else f"Knowledge indexing ({snapshot.subject_name}/{snapshot.source})"
            ),
        )
        summary.record(outcome)
    return summary


def index_knowledge(
    *,
    store: Any,
    config: AiConfig | None = None,
    names: list[str] | None = None,
    sources: list[str] | None = None,
    max_items: int | None = None,
    overwrite: bool = False,
    dry_run: bool = False,
    recreate_index: bool = False,
) -> JobSummary:
    """Index store snapshots through the standard sync workflow."""
    active = config or AiConfig()
    if recreate_index:
        require_full_recreate_scope(names=names, sources=sources, max_items=max_items)
    return index_snapshots(
        config=active,
        snapshots=store.list_indexable(
            names=names, sources=sources, max_items=max_items
        ),
        work_unit=store.work_unit(),
        reload=store.reload,
        overwrite=overwrite,
        dry_run=dry_run,
        recreate_index=recreate_index,
        snapshots_to_reset=store.list_succeeded() if recreate_index else None,
    )
