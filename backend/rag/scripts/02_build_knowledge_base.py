"""Ensure and synchronize one example Wikipedia scope in Azure Search."""

from __future__ import annotations

import argparse
import os

from mesozoica_ai.knowledge import (
    KnowledgeBaseSettings,
    KnowledgeDocument,
    create_knowledge_base,
    create_knowledge_index,
)
from mesozoica_ai.sources import WikipediaSource


def main(argv: list[str] | None = None) -> int:
    """Run index setup, exact-token chunking, embedding, and safe sync."""
    parser = argparse.ArgumentParser()
    parser.add_argument("title", nargs="?", default="Triceratops")
    args = parser.parse_args(argv)
    settings = KnowledgeBaseSettings()
    create_knowledge_index(settings).ensure()
    with WikipediaSource(user_agent=os.environ["WIKIPEDIA_USER_AGENT"]) as source:
        documents = source.fetch(args.title)
    subject = f"animal:{args.title.casefold()}"
    documents = [KnowledgeDocument.model_validate({
        **document.model_dump(mode="json"),
        "metadata": {
            **document.metadata.model_dump(mode="json", exclude_none=True),
            "namespace": "example", "subject_id": subject,
        },
    }) for document in documents]
    result = create_knowledge_base(settings).sync(
        documents,
        scope={"namespace": "example", "subject_id": subject, "source": "wikipedia"},
    )
    print(result.model_dump_json(indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
