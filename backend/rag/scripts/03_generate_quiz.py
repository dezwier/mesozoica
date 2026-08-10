"""Retrieve evidence and generate one cited quiz."""

from typing import Literal

from pydantic import Field

from mesozoica_ai import AiConfig, embed_query, prompt_rag, retrieve_chunks
from mesozoica_ai.common import CitedOutput
from mesozoica_ai.common.batch import DEFAULT_NAMESPACE

TITLE = "Triceratops"
SUBJECT_ID = f"animal:{TITLE.casefold()}"
QUERY = f"Distinctive facts about {TITLE} suitable for a quiz"


class Quiz(CitedOutput):
    question: str
    options: tuple[str, str, str, str]
    correct_index: Literal[0, 1, 2, 3]
    explanation: str = Field(min_length=1)


config = AiConfig()
chunks = retrieve_chunks(
    QUERY,
    query_embedding=embed_query(QUERY, config=config),
    filters={"namespace": DEFAULT_NAMESPACE, "subject_id": SUBJECT_ID},
    config=config,
)
quiz = prompt_rag(
    Quiz,
    query=QUERY,
    evidence=chunks,
    application_context={"language": "English", "difficulty": "medium"},
    config=config,
)
print(quiz.model_dump_json(indent=2))
