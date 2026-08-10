from __future__ import annotations

import logging
from datetime import datetime, timezone

from sqlmodel import Session, col, select

from app.features.ingestion.application.knowledge.acquire import (
    KnowledgeJobSummary,
    _normalize_sources,
)
from app.features.ingestion.models.rag_source_snapshot import (
    RAG_STATUS_FAILED,
    RAG_STATUS_PENDING,
    RAG_STATUS_RUNNING,
    RAG_STATUS_SUCCEEDED,
    RagSourceSnapshot,
)
from mesozoica_ai.knowledge import (
    AzureKnowledgeIndex,
    KnowledgeBase,
    KnowledgeDocument,
)

logger = logging.getLogger(__name__)


def index_dinosaur_knowledge(
    session: Session,
    *,
    knowledge: KnowledgeBase,
    index: AzureKnowledgeIndex,
    dinosaur_names: list[str] | None = None,
    sources: list[str] | None = None,
    max_items: int | None = None,
    overwrite: bool = False,
    dry_run: bool = False,
    recreate_index: bool = False,
) -> KnowledgeJobSummary:
    selected_sources = _normalize_sources(sources)
    if recreate_index and (
        dinosaur_names
        or max_items is not None
        or set(selected_sources) != {"wikipedia", "openalex"}
    ):
        raise ValueError(
            "--recreate-index must run unscoped: omit --dinos/--max-items and include both sources"
        )
    snapshots = _eligible_snapshots(
        session, dinosaur_names=dinosaur_names, sources=selected_sources
    )
    if max_items is not None:
        snapshots = snapshots[:max_items]
    summary = KnowledgeJobSummary(candidates=len(snapshots))
    if dry_run:
        summary.skipped = len(snapshots)
        return summary
    if recreate_index:
        index.recreate()
        acquired = session.exec(
            select(RagSourceSnapshot).where(
                RagSourceSnapshot.acquisition_status == RAG_STATUS_SUCCEEDED
            )
        ).all()
        for snapshot in acquired:
            snapshot.index_status = RAG_STATUS_PENDING
            snapshot.indexed_hash = None
            snapshot.indexed_pipeline_fingerprint = None
            snapshot.index_error = None
            snapshot.updated_at = _utc_now()
            session.add(snapshot)
        session.commit()
        snapshots = _eligible_snapshots(
            session, dinosaur_names=dinosaur_names, sources=selected_sources
        )
        if max_items is not None:
            snapshots = snapshots[:max_items]
        summary.candidates = len(snapshots)
    else:
        index.ensure()
    for snapshot in snapshots:
        if (
            snapshot.index_status == RAG_STATUS_SUCCEEDED
            and snapshot.indexed_hash == snapshot.content_hash
            and snapshot.indexed_pipeline_fingerprint == knowledge.pipeline_fingerprint
            and not overwrite
        ):
            summary.skipped += 1
            continue
        snapshot.index_status = RAG_STATUS_RUNNING
        snapshot.index_attempts += 1
        snapshot.index_started_at = _utc_now()
        snapshot.index_finished_at = None
        snapshot.index_error = None
        snapshot.updated_at = _utc_now()
        session.add(snapshot)
        session.commit()
        try:
            documents = [KnowledgeDocument.model_validate(item) for item in snapshot.documents]
            knowledge.sync(
                documents,
                scope={
                    "namespace": "mesozoica",
                    "subject_id": f"dinosaur:{snapshot.subject_id}",
                    "source": snapshot.source,
                },
            )
            snapshot.index_status = RAG_STATUS_SUCCEEDED
            snapshot.indexed_hash = snapshot.content_hash
            snapshot.indexed_pipeline_fingerprint = knowledge.pipeline_fingerprint
            snapshot.index_finished_at = _utc_now()
            snapshot.index_error = None
            summary.succeeded += 1
        except Exception as exc:
            session.rollback()
            snapshot = session.get(RagSourceSnapshot, snapshot.id)
            if snapshot is None:  # pragma: no cover - defensive
                raise
            snapshot.index_status = RAG_STATUS_FAILED
            snapshot.index_finished_at = _utc_now()
            snapshot.index_error = str(exc)[:4000]
            summary.failed += 1
            logger.exception(
                "Knowledge indexing failed for %s/%s", snapshot.subject_name, snapshot.source
            )
        snapshot.updated_at = _utc_now()
        session.add(snapshot)
        session.commit()
    return summary


def _eligible_snapshots(
    session: Session, *, dinosaur_names: list[str] | None, sources: list[str]
) -> list[RagSourceSnapshot]:
    statement = (
        select(RagSourceSnapshot)
        .where(
            RagSourceSnapshot.subject_kind == "dinosaur",
            RagSourceSnapshot.acquisition_status == RAG_STATUS_SUCCEEDED,
            col(RagSourceSnapshot.source).in_(sources),
        )
        .order_by(col(RagSourceSnapshot.subject_name), col(RagSourceSnapshot.source))
    )
    snapshots = list(session.exec(statement).all())
    if dinosaur_names:
        names = {name.strip().casefold() for name in dinosaur_names if name.strip()}
        snapshots = [
            snapshot for snapshot in snapshots if snapshot.subject_name.casefold() in names
        ]
    return snapshots


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)
