from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field, field_validator, model_validator

from mesozoica_ai.knowledge import KnowledgeBase, RetrievalRequest
from mesozoica_ai.rag import CitedOutput, Evidence, Rag


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


def generate_quiz_preview(
    *,
    knowledge: KnowledgeBase,
    rag: Rag,
    dinosaur_id: int,
    dinosaur_name: str,
    user_context: QuizUserContext | None = None,
) -> QuizQuestion:
    context = user_context or QuizUserContext()
    retrieval_query = (
        f"Interesting, distinctive, scientifically supported facts about {dinosaur_name} "
        f"for a {context.preferred_difficulty} multiple-choice quiz"
    )
    retrieval = knowledge.retrieve(RetrievalRequest(
        query=retrieval_query,
        filters={"namespace": "mesozoica", "subject_id": f"dinosaur:{dinosaur_id}"},
    ))
    evidence = [
        Evidence(
            id=chunk.id,
            document_id=chunk.document_id,
            text=chunk.text,
            source=chunk.metadata.source,
            url=chunk.metadata.source_url,
        )
        for chunk in retrieval.chunks
    ]
    result = rag.generate(
        QuizQuestion,
        query=retrieval_query,
        evidence=evidence,
        application_context=context,
        instructions=(
            f"Create exactly one new multiple-choice question about {dinosaur_name}. "
            "Use exactly four unique options and one correct answer. Match the requested "
            "language and difficulty, avoid previous topics, explain the answer briefly, "
            "and cite every chunk that supports the correct answer."
        ),
    )
    return result.output
