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

from app.features.assistant.schemas import AskResponse, PaperLink

ANSWER_INSTRUCTIONS = (
    "Answer the question using only the supplied evidence. "
    "Be concise and accurate. Cite every chunk that supports the answer."
)

_MAX_PAPERS = 3


def select_papers(chunk_records: list[dict[str, Any]], *, limit: int = _MAX_PAPERS) -> list[PaperLink]:
    """Pick up to ``limit`` unique docs with title+URL; OpenAlex first."""
    openalex: list[PaperLink] = []
    others: list[PaperLink] = []
    seen: set[str] = set()

    for record in chunk_records:
        title = (record.get("title") or "").strip()
        url = (record.get("source_url") or "").strip()
        if not title or not url:
            continue
        key = str(record.get("document_id") or url)
        if key in seen:
            continue
        seen.add(key)
        link = PaperLink(title=title, url=url)
        if record.get("source") == "openalex":
            openalex.append(link)
        else:
            others.append(link)

    picked = openalex[:limit]
    if len(picked) < limit:
        for link in others:
            if len(picked) >= limit:
                break
            picked.append(link)
    return picked


def ask_question(question: str, *, config: AiConfig | None = None) -> AskResponse:
    """Retrieve evidence, generate a grounded answer, and attach paper links."""
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
    return AskResponse(answer=answer.answer, papers=select_papers(records))
