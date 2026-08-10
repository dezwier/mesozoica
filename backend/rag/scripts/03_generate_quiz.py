"""Generate one strict, cited four-option quiz from indexed evidence."""

from __future__ import annotations

import argparse
from typing import Literal

from pydantic import Field

from mesozoica_ai.knowledge import (
    KnowledgeBaseSettings,
    RetrievalRequest,
    create_knowledge_base,
)
from mesozoica_ai.rag import CitedOutput, Evidence, RagSettings, create_rag


class Quiz(CitedOutput):
    """Minimal cited output schema used by this example."""

    question: str
    options: tuple[str, str, str, str]
    correct_index: Literal[0, 1, 2, 3]
    explanation: str = Field(min_length=1)


def main(argv: list[str] | None = None) -> int:
    """Retrieve and generate a quiz without application persistence."""
    parser = argparse.ArgumentParser()
    parser.add_argument("title", nargs="?", default="Triceratops")
    args = parser.parse_args(argv)
    subject = f"animal:{args.title.casefold()}"
    query = f"Distinctive facts about {args.title} suitable for a quiz"
    retrieval = create_knowledge_base(
        KnowledgeBaseSettings(), write_enabled=False
    ).retrieve(RetrievalRequest(
        query=query,
        filters={"namespace": "example", "subject_id": subject},
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
    result = create_rag(RagSettings()).generate(
        Quiz,
        query=query,
        evidence=evidence,
        application_context={"language": "English", "difficulty": "medium"},
    )
    print(result.output.model_dump_json(indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
