"""Minimal structured RAG example with static application context."""

from typing import Literal

from pydantic import BaseModel, Field

from mesozoica_ai.generation import validate_citations
from mesozoica_ai.knowledge import KnowledgeSettings, RetrievalRequest, create_structured_rag


class Quiz(BaseModel):
    question: str
    options: tuple[str, str, str, str]
    correct_index: Literal[0, 1, 2, 3]
    explanation: str
    source_chunk_ids: list[str] = Field(min_length=1)


rag = create_structured_rag(KnowledgeSettings())
result = rag.generate(
    Quiz,
    query="Create one interesting quiz question about Triceratops.",
    application_context={"language": "English", "difficulty": "medium"},
    retrieval=RetrievalRequest(
        query="Distinctive facts about Triceratops suitable for a quiz",
        filters={"namespace": "example", "subject_id": "animal:triceratops"},
    ),
)
validate_citations(result.output.source_chunk_ids, result.chunks)
print(result.output.model_dump_json(indent=2))
