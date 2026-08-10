"""Answer a field question from indexed dinosaur knowledge (script-4 pipeline)."""

from __future__ import annotations

from typing import Any

from mesozoica_ai.common import AiConfig
from mesozoica_ai.common.batch import DEFAULT_NAMESPACE
from mesozoica_ai.generate import (
    GroundedAnswer,
    prompt_rag,
    retrieved_chunk_record,
)
from mesozoica_ai.index import embed_query, retrieve_chunks

from app.features.assistant.schemas import AskResponse, SourceLink

ANSWER_INSTRUCTIONS = (
    "Answer the question using only the supplied evidence. "
    "Be concise and accurate. Cite every chunk that supports the answer."
)

_MAX_SOURCES = 3


def _display_title(record: dict[str, Any]) -> str:
    title = (record.get("title") or "").strip()
    if not title:
        return ""
    if record.get("source") != "wikipedia":
        return title
    section = (record.get("section") or "").strip()
    if not section or section.casefold() == "introduction":
        return title
    return f"{title} — {section}"


def select_sources(
    chunk_records: list[dict[str, Any]], *, limit: int = _MAX_SOURCES
) -> list[SourceLink]:
    """Pick up to ``limit`` unique top-ranked sources (wiki sections or papers)."""
    picked: list[SourceLink] = []
    seen: set[str] = set()

    for record in chunk_records:
        title = _display_title(record)
        url = (record.get("source_url") or "").strip()
        if not title or not url:
            continue
        key = str(record.get("document_id") or url)
        if key in seen:
            continue
        seen.add(key)
        kind = str(record.get("source") or "unknown")
        picked.append(SourceLink(title=title, url=url, kind=kind))
        if len(picked) >= limit:
            break
    return picked


def ask_question(question: str, *, config: AiConfig | None = None) -> AskResponse:
    """Retrieve evidence, generate a grounded answer, and attach source links."""
    query = question.strip()
    if not query:
        raise ValueError("question must not be blank")

    cfg = config or AiConfig()
    filters: dict[str, str] = {"namespace": DEFAULT_NAMESPACE}
    chunks = retrieve_chunks(
        query,
        query_embedding=embed_query(query, config=cfg),
        filters=filters,
        config=cfg,
    )
    answer = prompt_rag(
        GroundedAnswer,
        query=query,
        evidence=chunks,
        application_context=None,
        instructions=ANSWER_INSTRUCTIONS,
        config=cfg,
    )
    records = [retrieved_chunk_record(chunk) for chunk in chunks]
    return AskResponse(answer=answer.answer, sources=select_sources(records))
