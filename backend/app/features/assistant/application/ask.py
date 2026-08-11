"""Answer a field question from indexed dinosaur knowledge (script-4 pipeline)."""

from __future__ import annotations

import re
from typing import Any

from mesozoica_ai.common import AiConfig
from mesozoica_ai.common.batch import DEFAULT_NAMESPACE, DEFAULT_SUBJECT_KIND
from mesozoica_ai.generate import (
    GroundedAnswer,
    prompt_rag,
    retrieved_chunk_record,
)
from mesozoica_ai.index import embed_query, retrieve_chunks

from app.features.assistant.application.display_text import clean_display_title
from app.features.assistant.schemas import AskResponse, SourceLink

ANSWER_INSTRUCTIONS = (
    "Answer the question using only the supplied evidence. "
    "Be concise and accurate. Cite every chunk that supports the answer."
)

_SCOPED_INSTRUCTIONS = (
    "The player selected a dinosaur in application_context.selected_dinosaur. "
    "Treat that dinosaur as the subject of the question unless the question "
    "clearly asks about something else. Prefer evidence about that dinosaur. "
    "Answer using only the supplied evidence. Be concise and accurate. "
    "Cite every chunk that supports the answer."
)

_MAX_REFERENCES = 5
_WS_RE = re.compile(r"\s+")
_SOFT_HYPHEN_RE = re.compile("\u00ad+")


def _display_title(record: dict[str, Any]) -> str:
    title = clean_display_title(str(record.get("title") or ""))
    if not title:
        return ""
    if record.get("source") != "wikipedia":
        return title
    section = clean_display_title(str(record.get("section") or ""))
    if not section or section.casefold() == "introduction":
        return title
    return f"{title} — {section}"



def format_reference_text(text: str) -> str:
    """Collapse hard-wrapped chunk text into readable flowing prose."""
    cleaned = _SOFT_HYPHEN_RE.sub("", (text or "").replace("\r\n", "\n"))
    # Join hard line wraps; keep a single space between paragraphs.
    cleaned = cleaned.replace("\n", " ")
    return _WS_RE.sub(" ", cleaned).strip()


def select_references(
    chunk_records: list[dict[str, Any]],
    *,
    cited_ids: list[str] | None = None,
    limit: int = _MAX_REFERENCES,
) -> list[SourceLink]:
    """Return cited evidence chunks (fallback: top retrieved) with source links."""
    by_id = {
        str(record.get("id") or "").strip(): record
        for record in chunk_records
        if str(record.get("id") or "").strip()
    }
    ordered: list[dict[str, Any]] = []
    seen_ids: set[str] = set()
    for cid in cited_ids or []:
        key = str(cid).strip()
        record = by_id.get(key)
        if record is None or key in seen_ids:
            continue
        ordered.append(record)
        seen_ids.add(key)
        if len(ordered) >= limit:
            break
    if not ordered:
        for record in chunk_records:
            key = str(record.get("id") or "").strip()
            if not key or key in seen_ids:
                continue
            ordered.append(record)
            seen_ids.add(key)
            if len(ordered) >= limit:
                break

    refs: list[SourceLink] = []
    for record in ordered:
        title = _display_title(record)
        url = (record.get("source_url") or "").strip()
        text = format_reference_text(str(record.get("text") or ""))
        if not text:
            continue
        if not title:
            title = "Source"
        kind = str(record.get("source") or "unknown")
        refs.append(SourceLink(title=title, url=url, kind=kind, text=text))
    return refs


def _normalize_subject_id(subject_id: str) -> str:
    """Catalog ids are bare PKs; Azure chunks use ``kind:id``."""
    scoped = subject_id.strip()
    if scoped and ":" not in scoped:
        return f"{DEFAULT_SUBJECT_KIND}:{scoped}"
    return scoped


def _prompt_query(question: str, *, subject_name: str | None) -> str:
    """Fold the selected dinosaur into the request text when helpful."""
    name = (subject_name or "").strip()
    if not name:
        return question
    if name.casefold() in question.casefold():
        return question
    return f"About {name}: {question}"


def ask_question(
    question: str,
    *,
    subject_id: str | None = None,
    subject_name: str | None = None,
    config: AiConfig | None = None,
) -> AskResponse:
    """Retrieve evidence, generate a grounded answer, and attach source links."""
    query = question.strip()
    if not query:
        raise ValueError("question must not be blank")

    cfg = config or AiConfig()
    filters: dict[str, str] = {"namespace": DEFAULT_NAMESPACE}
    application_context: dict[str, str] | None = None
    instructions = ANSWER_INSTRUCTIONS

    scoped = _normalize_subject_id(subject_id or "")
    name = (subject_name or "").strip() or None
    if scoped:
        # Azure OData: subject_id eq 'dinosaur:<id>'
        filters["subject_id"] = scoped
        if name:
            application_context = {
                "selected_dinosaur": name,
                "subject_id": scoped,
            }
            instructions = _SCOPED_INSTRUCTIONS

    prompt_query = _prompt_query(query, subject_name=name)
    chunks = retrieve_chunks(
        prompt_query,
        query_embedding=embed_query(prompt_query, config=cfg),
        filters=filters,
        config=cfg,
    )
    answer = prompt_rag(
        GroundedAnswer,
        query=prompt_query,
        evidence=chunks,
        application_context=application_context,
        instructions=instructions,
        config=cfg,
    )
    records = [retrieved_chunk_record(chunk) for chunk in chunks]
    return AskResponse(
        answer=answer.answer,
        sources=select_references(
            records,
            cited_ids=list(answer.source_chunk_ids),
        ),
    )
