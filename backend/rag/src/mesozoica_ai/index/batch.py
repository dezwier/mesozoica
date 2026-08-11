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
from mesozoica_ai.common.errors import EmbeddingProviderError
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

    logger.info(
        "dinosaur_knowledge embed: %s acquired row(s); %s pending, %s already embedded",
        len(snapshots),
        len(pending),
        already_embedded,
    )
    summary = JobSummary(candidates=len(snapshots))
    summary.skipped = already_embedded
    work_unit: UnitOfWork = _RepoUnitOfWork(repo)
    # One Azure OpenAI client for the whole run. Recreating per dinosaur races
    # Foundry routing and surfaces intermittent unknown_model 400s.
    embedder = build_embedder(active)
    logger.info(
        "Probing embedding deployment %s (%s dims)",
        active.embedding_deployment,
        active.embedding_dimensions,
    )
    try:
        embedder.embed_query("mesozoica embedding probe")
    except Exception as exc:
        raise EmbeddingProviderError(
            f"Embedding probe failed for deployment "
            f"{active.embedding_deployment!r}: {exc}"
        ) from exc

    for snapshot in pending:
        label = f"{snapshot.subject_name}/{snapshot.source}"
        prepare_result: dict[str, Any] = {}

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

        def reload(row: Any) -> Any:
            loaded = repo.get_source(
                subject_kind=row.subject_kind,
                subject_id=row.subject_id,
                source=row.source,
            )
            if loaded is None:
                raise RuntimeError(f"Missing knowledge source after failure: {row.id}")
            return loaded

        logger.info("%s: embedding", label)
        try:
            outcome = run_resumable_item(
                work_unit,
                snapshot,
                should_run=lambda row: True,
                begin=begin_embedding,
                work=work,
                complete=complete,
                fail=fail_embedding,
                reload=reload,
                label=label,
                reraise=lambda exc: isinstance(exc, EmbeddingProviderError),
            )
        except EmbeddingProviderError as exc:
            summary.failed += 1
            logger.error(
                "Stopping embed run — Azure embedding deployment unavailable: %s",
                exc,
            )
            return summary
        if outcome == "succeeded":
            prepared = prepare_result.get("prepared")
            if prepared is not None:
                logger.info(
                    "%s: done embed=%s reuse=%s chunks=%s",
                    label,
                    prepared.embedded_count,
                    prepared.reused_count,
                    prepared.chunk_count,
                )
        elif outcome == "failed":
            logger.error("%s: failed", label)
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
        logger.info("Azure index ready (%s)", getattr(active, "search_index", None) or "?")

    fingerprint = pipeline_fingerprint(config=active)
    store = build_store(active, write_enabled=False)
    pending = []
    already_indexed = 0
    drift_resets = 0
    verify_total = sum(
        1
        for snapshot in snapshots
        if snapshot.embed_status == "succeeded"
        and not indexing_needed(
            snapshot, pipeline_fingerprint=fingerprint, overwrite=overwrite
        )
    )
    verify_done = 0
    if verify_total:
        logger.info(
            "Verifying Azure keys for %s already-indexed source(s)…",
            verify_total,
        )
    for snapshot in snapshots:
        label = f"{snapshot.subject_name}/{snapshot.source}"
        if snapshot.embed_status != "succeeded":
            logger.info("%s: skip ingest (embed_status=%s)", label, snapshot.embed_status)
            continue
        chunks = repo.list_chunks(snapshot)
        if not chunks:
            logger.info("%s: skip ingest (no chunks)", label)
            continue
        if indexing_needed(
            snapshot, pipeline_fingerprint=fingerprint, overwrite=overwrite
        ):
            pending.append(snapshot)
            continue
        chunk_ids = {chunk.id for chunk in chunks}
        verify_done += 1
        if verify_done == 1 or verify_done % 50 == 0 or verify_done == verify_total:
            logger.info(
                "Azure verify progress %s/%s (latest %s, %s chunks)",
                verify_done,
                verify_total,
                label,
                len(chunk_ids),
            )
        try:
            # Scoped search (one query per dino) instead of N get_document calls.
            azure_ids = set(store.get_chunk_states(snapshot_scope(snapshot)))
        except Exception as exc:
            logger.warning("%s: Azure verify failed (%s); re-syncing", label, exc)
            reset_indexing(snapshot)
            repo.save_source(snapshot)
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
    logger.info(
        "dinosaur_knowledge ingest: %s embedded row(s); %s pending, %s already indexed%s",
        len(eligible),
        len(pending),
        already_indexed,
        f", {drift_resets} Azure drift" if drift_resets else "",
    )
    summary = JobSummary(candidates=len(eligible))
    summary.skipped = already_indexed + (len(snapshots) - len(eligible))

    for snapshot in pending:
        label = f"{snapshot.subject_name}/{snapshot.source}"
        sync_result: dict[str, Any] = {}

        def work(row: Any, *, _result=sync_result) -> None:
            _result["result"] = sync_embedded_chunks(
                repo.list_chunks(row),
                scope=snapshot_scope(row),
                config=active,
            )

        def reload(row: Any) -> Any:
            loaded = repo.get_source(
                subject_kind=row.subject_kind,
                subject_id=row.subject_id,
                source=row.source,
            )
            if loaded is None:
                raise RuntimeError(f"Missing knowledge source after failure: {row.id}")
            return loaded

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
                    result.embedded_count,
                    result.skipped_count,
                    result.metadata_updated_count,
                    result.deleted_count,
                )
        elif outcome == "failed":
            logger.error("%s: failed", label)
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
    return list(dict.fromkeys(normalized))
