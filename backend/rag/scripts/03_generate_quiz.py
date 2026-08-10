"""embed_query → retrieve_chunks → prompt_rag for one cited quiz."""

from __future__ import annotations

import argparse
from typing import Literal

from pydantic import Field

from mesozoica_ai import AiConfig, embed_query, prompt_rag, retrieve_chunks
from mesozoica_ai.common import CitedOutput


class Quiz(CitedOutput):
    question: str
    options: tuple[str, str, str, str]
    correct_index: Literal[0, 1, 2, 3]
    explanation: str = Field(min_length=1)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("title", nargs="?", default="Triceratops")
    args = parser.parse_args(argv)
    subject = f"animal:{args.title.casefold()}"
    query = f"Distinctive facts about {args.title} suitable for a quiz"
    config = AiConfig()

    query_vector = embed_query(query, config=config)
    chunks = retrieve_chunks(
        query,
        query_embedding=query_vector,
        filters={"namespace": "example", "subject_id": subject},
        config=config,
    )
    quiz = prompt_rag(
        Quiz,
        query=query,
        evidence=chunks,
        application_context={"language": "English", "difficulty": "medium"},
        config=config,
    )
    print(quiz.model_dump_json(indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
