"""Checkpointed multi-subject source acquisition."""

from __future__ import annotations

from collections.abc import Callable, Mapping, Sequence
from typing import Any, TypeVar

from mesozoica_ai.common.batch import (
    DEFAULT_NAMESPACE,
    DEFAULT_SUBJECT_KIND,
    JobSummary,
    subject_metadata,
    subject_query,
)
from mesozoica_ai.common.checkpoints import (
    acquisition_needed,
    begin_acquisition,
    complete_acquisition,
    fail_acquisition,
)
from mesozoica_ai.common.resume import UnitOfWork, run_resumable_item
from mesozoica_ai.sources import RetrievedDocuments, normalize_sources

SubjectT = TypeVar("SubjectT")
CheckpointT = TypeVar("CheckpointT")
RetrieveFn = Callable[..., RetrievedDocuments]


def acquire_sources(
    *,
    subjects: Sequence[SubjectT],
    retrievers: Mapping[str, RetrieveFn],
    get_or_create: Callable[[SubjectT, str], CheckpointT],
    work_unit: UnitOfWork,
    sources: list[str] | None = None,
    reload: Callable[[SubjectT, str], CheckpointT] | None = None,
    query_for: Callable[[SubjectT, str], str] | None = None,
    metadata_for: Callable[[SubjectT, str], dict[str, Any]] | None = None,
    max_items: int | None = None,
    overwrite: bool = False,
    dry_run: bool = False,
    label_for: Callable[[SubjectT, str], str] | None = None,
    namespace: str = DEFAULT_NAMESPACE,
    subject_kind: str = DEFAULT_SUBJECT_KIND,
) -> JobSummary:
    """Acquire every subject/source pair through checkpointed retrieval."""
    selected_sources = normalize_sources(sources)
    missing = [source for source in selected_sources if source not in retrievers]
    if missing:
        raise ValueError(f"Missing retrievers for sources: {', '.join(missing)}")
    selected_subjects = subjects[:max_items] if max_items is not None else list(subjects)
    resolve_query = query_for or subject_query
    resolve_metadata = metadata_for or (
        lambda subject, source: subject_metadata(
            subject, source, namespace=namespace, subject_kind=subject_kind
        )
    )
    resolve_reload = reload or get_or_create
    summary = JobSummary(candidates=len(selected_subjects) * len(selected_sources))
    for subject in selected_subjects:
        for source in selected_sources:
            if dry_run:
                summary.skipped += 1
                continue
            checkpoint = get_or_create(subject, source)
            retrieved: dict[str, RetrievedDocuments] = {}

            def work(
                _row: CheckpointT,
                *,
                _subject=subject,
                _source=source,
                _retrieved=retrieved,
            ) -> None:
                _retrieved["result"] = retrievers[_source](
                    resolve_query(_subject, _source),
                    metadata=resolve_metadata(_subject, _source),
                )

            outcome = run_resumable_item(
                work_unit,
                checkpoint,
                should_run=lambda row: acquisition_needed(row, overwrite=overwrite),
                begin=begin_acquisition,
                work=work,
                complete=lambda row, _retrieved=retrieved: complete_acquisition(
                    row, _retrieved["result"]
                ),
                fail=fail_acquisition,
                reload=lambda _row, _subject=subject, _source=source: resolve_reload(
                    _subject, _source
                ),
                label=(
                    label_for(subject, source)
                    if label_for
                    else f"Knowledge acquisition ({subject.name}/{source})"
                ),
            )
            summary.record(outcome)
    return summary


def acquire_knowledge(
    *,
    subjects: Sequence[SubjectT],
    retrievers: Mapping[str, RetrieveFn],
    store: Any,
    sources: list[str] | None = None,
    max_items: int | None = None,
    overwrite: bool = False,
    dry_run: bool = False,
) -> JobSummary:
    """Acquire sources through a SnapshotStore-backed checkpoint."""
    return acquire_sources(
        subjects=subjects,
        sources=sources,
        retrievers=retrievers,
        get_or_create=store.get_or_create,
        work_unit=store.work_unit(),
        max_items=max_items,
        overwrite=overwrite,
        dry_run=dry_run,
    )
