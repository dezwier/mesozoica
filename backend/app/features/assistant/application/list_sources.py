"""List indexed knowledge documents for one dinosaur, grouped by source."""

from __future__ import annotations

from typing import Any
from urllib.parse import urldefrag

from sqlmodel import col, select

from app.features.assistant.application.display_text import clean_display_title
from app.features.assistant.schemas import (
    KnowledgeSourceGroup,
    KnowledgeSourceItem,
    KnowledgeSourcesResponse,
)
from app.features.ingestion.application.dinosaur_knowledge.repository import (
    dinosaur_knowledge_repo,
)
from app.features.ingestion.models import (
    KNOWLEDGE_STATUS_SUCCEEDED,
    DinosaurKnowledgeSource,
)
from mesozoica_ai.common.batch import DEFAULT_SUBJECT_KIND

_KIND_ORDER = ("wikipedia", "openalex")


def list_subject_sources(
    session: Any, subject_id: str
) -> KnowledgeSourcesResponse | None:
    """Return deduped wiki/paper links for an indexed dinosaur, or None if missing."""
    sid = str(subject_id).strip()
    if not sid:
        return None

    repo = dinosaur_knowledge_repo(session)
    source_rows = list(
        session.exec(
            select(DinosaurKnowledgeSource)
            .where(
                DinosaurKnowledgeSource.subject_kind == DEFAULT_SUBJECT_KIND,
                DinosaurKnowledgeSource.subject_id == sid,
                DinosaurKnowledgeSource.index_status == KNOWLEDGE_STATUS_SUCCEEDED,
            )
            .order_by(col(DinosaurKnowledgeSource.source))
        ).all()
    )
    if not source_rows:
        return None

    subject_name = str(source_rows[0].subject_name).strip() or sid
    by_kind: dict[str, list[KnowledgeSourceItem]] = {}
    seen: set[tuple[str, str]] = set()

    for source_row in source_rows:
        kind = str(source_row.source).strip() or "unknown"
        for document in repo.list_documents(source_row):
            meta = document.metadata
            url = (meta.source_url or "").strip()
            title = clean_display_title(meta.title or "")
            if not url or not title:
                continue
            # Wikipedia sections share one page — strip fragment for a single link.
            if kind == "wikipedia":
                url, _ = urldefrag(url)
            provenance = (meta.source_id or "").strip() or url
            key = (kind, provenance)
            if key in seen:
                continue
            seen.add(key)
            by_kind.setdefault(kind, []).append(
                KnowledgeSourceItem(title=title, url=url, kind=kind)
            )

    groups: list[KnowledgeSourceGroup] = []
    for kind in _KIND_ORDER:
        items = by_kind.pop(kind, None)
        if items:
            groups.append(KnowledgeSourceGroup(kind=kind, items=items))
    for kind in sorted(by_kind):
        groups.append(KnowledgeSourceGroup(kind=kind, items=by_kind[kind]))

    return KnowledgeSourcesResponse(
        subject_id=sid,
        subject_name=subject_name,
        groups=groups,
    )
