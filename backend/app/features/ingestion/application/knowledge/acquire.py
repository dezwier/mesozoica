from __future__ import annotations

import hashlib
import json
import logging
from datetime import datetime, timezone
from typing import Protocol

from pydantic import BaseModel
from sqlmodel import Session, select

from app.features.ingestion.models.rag_source_snapshot import (
    RAG_STATUS_FAILED,
    RAG_STATUS_PENDING,
    RAG_STATUS_RUNNING,
    RAG_STATUS_SUCCEEDED,
    RagSourceSnapshot,
)
from app.features.specimens.public import DinosaurKnowledgeSubject
from mesozoica_ai.knowledge import KnowledgeDocument

logger = logging.getLogger(__name__)

SUPPORTED_KNOWLEDGE_SOURCES = ("wikipedia", "openalex")


class WikipediaProvider(Protocol):
    def fetch(self, title: str) -> list[KnowledgeDocument]: ...


class OpenAlexProvider(Protocol):
    def search(self, query: str, *, limit: int = 10) -> list[KnowledgeDocument]: ...


class KnowledgeJobSummary(BaseModel):
    candidates: int = 0
    succeeded: int = 0
    skipped: int = 0
    failed: int = 0

    @property
    def exit_code(self) -> int:
        return 1 if self.failed else 0


def acquire_dinosaur_knowledge(
    session: Session,
    *,
    subjects: list[DinosaurKnowledgeSubject],
    wikipedia: WikipediaProvider | None,
    openalex: OpenAlexProvider | None,
    sources: list[str] | None = None,
    max_items: int | None = None,
    overwrite: bool = False,
    dry_run: bool = False,
    openalex_limit: int = 10,
) -> KnowledgeJobSummary:
    selected_sources = _normalize_sources(sources)
    selected_subjects = subjects[:max_items] if max_items is not None else subjects
    summary = KnowledgeJobSummary(candidates=len(selected_subjects) * len(selected_sources))
    for subject in selected_subjects:
        for source in selected_sources:
            if dry_run:
                summary.skipped += 1
                continue
            snapshot = _get_or_create_snapshot(session, subject=subject, source=source)
            if snapshot.acquisition_status == RAG_STATUS_SUCCEEDED and not overwrite:
                summary.skipped += 1
                continue
            snapshot.acquisition_status = RAG_STATUS_RUNNING
            snapshot.acquisition_attempts += 1
            snapshot.acquisition_started_at = _utc_now()
            snapshot.acquisition_finished_at = None
            snapshot.acquisition_error = None
            snapshot.updated_at = _utc_now()
            session.add(snapshot)
            session.commit()
            try:
                if source == "wikipedia":
                    if wikipedia is None:
                        raise RuntimeError("Wikipedia provider is not configured")
                    documents = wikipedia.fetch(subject.wikipedia_title)
                else:
                    if openalex is None:
                        raise RuntimeError("OpenAlex provider is not configured")
                    documents = openalex.search(subject.name, limit=openalex_limit)
                documents = [_with_subject_metadata(document, subject) for document in documents]
                serialized = [document.model_dump(mode="json") for document in documents]
                content_hash = hashlib.sha256(
                    json.dumps(serialized, sort_keys=True, ensure_ascii=False).encode("utf-8")
                ).hexdigest()
                source_hash = _source_hash(documents)
                changed = snapshot.content_hash != content_hash
                snapshot.documents = serialized
                snapshot.content_hash = content_hash
                snapshot.source_hash = source_hash
                snapshot.source_version = _source_version(documents)
                snapshot.acquisition_status = RAG_STATUS_SUCCEEDED
                snapshot.acquisition_finished_at = _utc_now()
                snapshot.acquisition_error = None
                if changed:
                    snapshot.index_status = RAG_STATUS_PENDING
                    snapshot.indexed_hash = None
                    snapshot.index_error = None
                summary.succeeded += 1
            except Exception as exc:
                session.rollback()
                snapshot = _get_or_create_snapshot(session, subject=subject, source=source)
                snapshot.acquisition_status = RAG_STATUS_FAILED
                snapshot.acquisition_finished_at = _utc_now()
                snapshot.acquisition_error = str(exc)[:4000]
                summary.failed += 1
                logger.exception("Knowledge acquisition failed for %s/%s", subject.name, source)
            snapshot.updated_at = _utc_now()
            session.add(snapshot)
            session.commit()
    return summary


def _get_or_create_snapshot(
    session: Session, *, subject: DinosaurKnowledgeSubject, source: str
) -> RagSourceSnapshot:
    snapshot = session.exec(
        select(RagSourceSnapshot).where(
            RagSourceSnapshot.subject_kind == "dinosaur",
            RagSourceSnapshot.subject_id == str(subject.id),
            RagSourceSnapshot.source == source,
        )
    ).first()
    if snapshot is None:
        snapshot = RagSourceSnapshot(
            subject_kind="dinosaur",
            subject_id=str(subject.id),
            subject_name=subject.name,
            source=source,
        )
        session.add(snapshot)
        session.commit()
        session.refresh(snapshot)
    elif snapshot.subject_name != subject.name:
        snapshot.subject_name = subject.name
    return snapshot


def _with_subject_metadata(
    document: KnowledgeDocument, subject: DinosaurKnowledgeSubject
) -> KnowledgeDocument:
    metadata = document.metadata.copy()
    metadata.update(
        namespace="mesozoica",
        subject_id=f"dinosaur:{subject.id}",
        subject_name=subject.name,
    )
    return document.model_copy(update={"metadata": metadata})


def _source_version(documents: list[KnowledgeDocument]) -> str | None:
    versions = sorted(
        {
            str(document.metadata["source_version"])
            for document in documents
            if document.metadata.get("source_version")
        }
    )
    return ",".join(versions)[:255] or None


def _source_hash(documents: list[KnowledgeDocument]) -> str:
    provenance = [
        {
            "id": document.id,
            "source_id": document.metadata.get("source_id"),
            "source_version": document.metadata.get("source_version"),
            "source_url": document.metadata.get("source_url"),
            "published_at": document.metadata.get("published_at"),
            "updated_at": document.metadata.get("updated_at"),
        }
        for document in documents
    ]
    return hashlib.sha256(
        json.dumps(provenance, sort_keys=True, ensure_ascii=False, default=str).encode(
            "utf-8"
        )
    ).hexdigest()


def _normalize_sources(sources: list[str] | None) -> list[str]:
    values = list(SUPPORTED_KNOWLEDGE_SOURCES if not sources else sources)
    normalized = [value.strip().casefold() for value in values if value.strip()]
    unknown = sorted(set(normalized) - set(SUPPORTED_KNOWLEDGE_SOURCES))
    if unknown:
        raise ValueError(f"Unsupported knowledge sources: {', '.join(unknown)}")
    return list(dict.fromkeys(normalized))


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)
