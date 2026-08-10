"""Acquire Wikipedia/OpenAlex documents for many subjects into a checkpoint table."""

from __future__ import annotations

from typing import Any

from mesozoica_ai.common.batch import JobSummary, subject_metadata, subject_query
from mesozoica_ai.common.checkpoints import acquisition_needed
from mesozoica_ai.sources.openalex import retrieve_openalex
from mesozoica_ai.sources.store import store_documents
from mesozoica_ai.sources.wikipedia import retrieve_wikipedia

SUPPORTED_SOURCES = ("wikipedia", "openalex")


def acquire_knowledge(
    session: Any,
    model: type[Any],
    *,
    subjects: list[Any],
    user_agent: str,
    openalex_api_key: str = "",
    openalex_limit: int = 10,
    sources: list[str] | None = None,
    max_items: int | None = None,
    overwrite: bool = False,
    dry_run: bool = False,
) -> JobSummary:
    """Fetch and store Wikipedia/OpenAlex docs for each subject."""
    selected = _normalize_sources(sources)
    if not dry_run and "openalex" in selected and not openalex_api_key:
        raise RuntimeError("OPENALEX_API_KEY is required for OpenAlex acquisition")

    selected_subjects = subjects[:max_items] if max_items is not None else list(subjects)
    summary = JobSummary(candidates=len(selected_subjects) * len(selected))
    for subject in selected_subjects:
        for source in selected:
            if dry_run:
                summary.skipped += 1
                continue
            if _already_succeeded(session, model, subject, source, overwrite=overwrite):
                summary.skipped += 1
                continue
            metadata = subject_metadata(subject, source)
            try:
                documents = _retrieve(
                    subject,
                    source,
                    user_agent=user_agent,
                    openalex_api_key=openalex_api_key,
                    openalex_limit=openalex_limit,
                    metadata=metadata,
                )
                outcome = store_documents(
                    session,
                    model,
                    subject=subject,
                    source=source,
                    documents=documents,
                    overwrite=overwrite,
                )
            except Exception as exc:
                outcome = store_documents(
                    session,
                    model,
                    subject=subject,
                    source=source,
                    error=exc,
                    overwrite=overwrite,
                )
            summary.record(outcome)
    return summary


def _retrieve(
    subject: Any,
    source: str,
    *,
    user_agent: str,
    openalex_api_key: str,
    openalex_limit: int,
    metadata: dict[str, Any],
):
    query = subject_query(subject, source)
    if source == "wikipedia":
        return retrieve_wikipedia(query, user_agent=user_agent, metadata=metadata)
    return retrieve_openalex(
        query,
        api_key=openalex_api_key,
        user_agent=user_agent,
        limit=openalex_limit,
        metadata=metadata,
    )


def _already_succeeded(
    session: Any,
    model: type[Any],
    subject: Any,
    source: str,
    *,
    overwrite: bool,
) -> bool:
    from sqlmodel import select

    from mesozoica_ai.common.batch import DEFAULT_SUBJECT_KIND

    row = session.exec(
        select(model).where(
            model.subject_kind == DEFAULT_SUBJECT_KIND,
            model.subject_id == str(subject.id),
            model.source == source,
        )
    ).first()
    return row is not None and not acquisition_needed(row, overwrite=overwrite)


def _normalize_sources(sources: list[str] | None) -> list[str]:
    values = SUPPORTED_SOURCES if not sources else sources
    normalized = [value.strip().casefold() for value in values if value.strip()]
    unknown = sorted(set(normalized) - set(SUPPORTED_SOURCES))
    if unknown:
        raise ValueError(f"Unsupported knowledge sources: {', '.join(unknown)}")
    return list(dict.fromkeys(normalized))
