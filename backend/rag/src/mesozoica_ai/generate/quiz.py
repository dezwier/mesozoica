"""Quiz helpers built on ``answer_from_index``."""

from __future__ import annotations

from collections.abc import Sequence
from typing import Any, Literal

from pydantic import BaseModel, Field, field_validator, model_validator

from mesozoica_ai.common.batch import DEFAULT_NAMESPACE, DEFAULT_SUBJECT_KIND
from mesozoica_ai.common.config import AiConfig
from mesozoica_ai.common.models import CitedOutput
from mesozoica_ai.generate.answer import answer_from_index


class QuizUserContext(BaseModel):
    language: str = "English"
    knowledge_level: str = "intermediate"
    preferred_difficulty: Literal["easy", "medium", "hard"] = "medium"
    previous_topics: list[str] = Field(default_factory=list)


class QuizQuestion(CitedOutput):
    question: str = Field(min_length=1)
    topic: str = Field(min_length=1)
    difficulty: Literal["easy", "medium", "hard"]
    # list[str] (not tuple) so OpenAI json_schema structured output gets ``items``.
    options: list[str] = Field(min_length=4, max_length=4)
    correct_index: Literal[0, 1, 2, 3]
    explanation: str = Field(min_length=1)

    @field_validator("question", "topic", "explanation")
    @classmethod
    def nonblank_text(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("Quiz text fields must not be blank")
        return value.strip()

    @model_validator(mode="after")
    def unique_options(self) -> QuizQuestion:
        stripped = [option.strip() for option in self.options]
        if len(stripped) != 4:
            raise ValueError("Quiz options must contain exactly four answers")
        if not all(stripped):
            raise ValueError("Quiz options must not be blank")
        normalized = {option.casefold() for option in stripped}
        if len(normalized) != 4:
            raise ValueError("Quiz options must be unique")
        self.options = stripped
        return self


def generate_quiz(
    *,
    config: AiConfig | None = None,
    subject_id: int | str | None = None,
    subject_name: str | None = None,
    subject: Any | None = None,
    user_context: QuizUserContext | None = None,
    namespace: str = DEFAULT_NAMESPACE,
    subject_kind: str = DEFAULT_SUBJECT_KIND,
    mode: Any | None = None,
) -> QuizQuestion:
    """Generate one cited multiple-choice quiz from indexed evidence."""
    if subject is not None:
        subject_id = subject.id
        subject_name = subject.name
    if subject_id is None or not subject_name:
        raise ValueError("generate_quiz requires subject or subject_id/subject_name")
    active = config or AiConfig()
    context = user_context or QuizUserContext()
    query, filters, instructions = quiz_retrieval_plan(
        subject_id=subject_id,
        subject_name=subject_name,
        user_context=context,
        namespace=namespace,
        subject_kind=subject_kind,
    )
    return answer_from_index(
        QuizQuestion,
        query=query,
        filters=filters,
        config=active,
        application_context=context,
        instructions=instructions,
        mode=mode,
    )


def quiz_retrieval_plan(
    *,
    subject_id: int | str,
    subject_name: str,
    user_context: QuizUserContext | None = None,
    namespace: str = DEFAULT_NAMESPACE,
    subject_kind: str = DEFAULT_SUBJECT_KIND,
) -> tuple[str, dict[str, Any], str]:
    """Return ``(query, filters, instructions)`` used for quiz retrieval + generation."""
    context = user_context or QuizUserContext()
    query = (
        f"Interesting, distinctive, scientifically supported facts about {subject_name} "
        f"for a {context.preferred_difficulty} multiple-choice quiz"
    )
    filters = {
        "namespace": namespace,
        "subject_id": f"{subject_kind}:{subject_id}",
    }
    instructions = (
        f"Create exactly one new multiple-choice question about {subject_name}. "
        "Use exactly four unique options and one correct answer. Match the requested "
        "language and difficulty, avoid previous topics, explain the answer briefly, "
        "and cite every chunk that supports the correct answer."
    )
    return query, filters, instructions


def retrieved_chunk_record(chunk: Any) -> dict[str, Any]:
    """Flatten a retrieved chunk into clear identity, ranking, and provenance fields."""
    metadata = chunk.metadata
    if hasattr(metadata, "model_dump"):
        meta = metadata.model_dump(mode="json", exclude_none=True)
    else:
        meta = dict(metadata or {})
    return {
        "id": chunk.id,
        "document_id": chunk.document_id,
        "chunk_index": chunk.chunk_index,
        "score": chunk.score,
        "reranker_score": chunk.reranker_score,
        "source": meta.get("source"),
        "source_id": meta.get("source_id"),
        "title": meta.get("title"),
        "section": meta.get("section"),
        "section_path": meta.get("section_path") or [],
        "source_url": meta.get("source_url"),
        "namespace": meta.get("namespace"),
        "subject_id": meta.get("subject_id"),
        "subject_name": meta.get("subject_name"),
        "published_at": meta.get("published_at"),
        "text": chunk.text,
    }


def format_chunk_log_lines(
    records: Sequence[dict[str, Any]], *, preview_chars: int = 100
) -> list[str]:
    """Compact log lines: one metadata line + one text preview per chunk."""
    lines = [f"retrieved {len(records)} chunk(s)"]
    for index, record in enumerate(records, start=1):
        score = record.get("score")
        score_s = f"{float(score):.3f}" if score is not None else "?"
        rerank = record.get("reranker_score")
        rerank_s = f" rerank={float(rerank):.2f}" if rerank is not None else ""
        source = record.get("source") or "?"
        title = (record.get("title") or "").strip() or "?"
        section = (record.get("section") or "").strip()
        chunk_id = str(record.get("id") or "")
        id_s = chunk_id[:10] if chunk_id else "?"
        where = f"{title} · {section}" if section else title
        lines.append(f"  [{index}] {score_s}{rerank_s} {source} | {where} | {id_s}")
        text = " ".join(str(record.get("text") or "").split())
        if len(text) > preview_chars:
            text = text[: preview_chars - 1].rstrip() + "…"
        lines.append(f"       {text or '(empty)'}")
    return lines


def log_retrieved_chunks(
    logger: Any, records: Sequence[dict[str, Any]], *, preview_chars: int = 100
) -> None:
    """Log retrieved chunks with compact metadata + text preview."""
    for line in format_chunk_log_lines(records, preview_chars=preview_chars):
        logger.info("%s", line)


def require_one_subject(subjects: Sequence[Any], *, requested: str | None = None) -> Any:
    """Return the sole subject or raise a clear error."""
    if len(subjects) != 1:
        label = requested or "subject"
        raise ValueError(f"Expected exactly one subject for {label}")
    return subjects[0]


def print_model(model: Any) -> int:
    """Print a Pydantic model as JSON and return success."""
    print(model.model_dump_json(indent=2))
    return 0
