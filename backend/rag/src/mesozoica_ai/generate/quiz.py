"""Embed, retrieve, and generate in one call; quiz helpers."""

from __future__ import annotations

from collections.abc import Sequence
from typing import Any, Literal

from pydantic import BaseModel, Field, field_validator, model_validator

from mesozoica_ai.common.batch import DEFAULT_NAMESPACE, DEFAULT_SUBJECT_KIND
from mesozoica_ai.common.config import AiConfig
from mesozoica_ai.common.models import CitedOutput
from mesozoica_ai.generate.prompt import prompt_rag
from mesozoica_ai.index import embed_query, retrieve_chunks


def answer_from_index(
    output_model: type[Any],
    *,
    query: str,
    filters: dict[str, Any],
    config: AiConfig,
    application_context: Any = None,
    instructions: str = "Answer using only the supplied evidence.",
) -> Any:
    """Embed, retrieve, and generate in one call."""
    chunks = retrieve_chunks(
        query,
        query_embedding=embed_query(query, config=config),
        filters=filters,
        config=config,
    )
    return prompt_rag(
        output_model,
        query=query,
        evidence=chunks,
        application_context=application_context,
        instructions=instructions,
        config=config,
    )


class QuizUserContext(BaseModel):
    language: str = "English"
    knowledge_level: str = "intermediate"
    preferred_difficulty: Literal["easy", "medium", "hard"] = "medium"
    previous_topics: list[str] = Field(default_factory=list)


class QuizQuestion(CitedOutput):
    question: str = Field(min_length=1)
    topic: str = Field(min_length=1)
    difficulty: Literal["easy", "medium", "hard"]
    options: tuple[str, str, str, str]
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
        if not all(stripped):
            raise ValueError("Quiz options must not be blank")
        normalized = {option.casefold() for option in stripped}
        if len(normalized) != 4:
            raise ValueError("Quiz options must be unique")
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
) -> QuizQuestion:
    """Generate one cited multiple-choice quiz from indexed evidence."""
    if subject is not None:
        subject_id = subject.id
        subject_name = subject.name
    if subject_id is None or not subject_name:
        raise ValueError("generate_quiz requires subject or subject_id/subject_name")
    active = config or AiConfig()
    context = user_context or QuizUserContext()
    query = (
        f"Interesting, distinctive, scientifically supported facts about {subject_name} "
        f"for a {context.preferred_difficulty} multiple-choice quiz"
    )
    return answer_from_index(
        QuizQuestion,
        query=query,
        filters={
            "namespace": namespace,
            "subject_id": f"{subject_kind}:{subject_id}",
        },
        config=active,
        application_context=context,
        instructions=(
            f"Create exactly one new multiple-choice question about {subject_name}. "
            "Use exactly four unique options and one correct answer. Match the requested "
            "language and difficulty, avoid previous topics, explain the answer briefly, "
            "and cite every chunk that supports the correct answer."
        ),
    )


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
