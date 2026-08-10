"""Retrieve → chunk → embed → index one Wikipedia subject into Azure Search."""

from __future__ import annotations

import argparse
import os

from mesozoica_ai import (
    AiConfig,
    chunk_documents,
    embed_chunks,
    ensure_index,
    index_chunks,
    retrieve_wikipedia,
    sync_documents,
)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("title", nargs="?", default="Triceratops")
    parser.add_argument(
        "--sync",
        action="store_true",
        help="use sync_documents (safe incremental ingest) instead of chunk/embed/index",
    )
    args = parser.parse_args(argv)
    config = AiConfig()
    subject = f"animal:{args.title.casefold()}"
    scope = {"namespace": "example", "subject_id": subject, "source": "wikipedia"}
    documents = retrieve_wikipedia(
        args.title,
        user_agent=os.environ["WIKIPEDIA_USER_AGENT"],
        metadata={"namespace": "example", "subject_id": subject},
    ).documents
    ensure_index(config=config)
    if args.sync:
        result = sync_documents(documents, scope=scope, config=config)
        print(result.model_dump_json(indent=2))
        return 0

    chunks = chunk_documents(documents, config=config)
    embedded = embed_chunks(chunks, config=config)
    result = index_chunks(embedded, config=config)
    print(result.model_dump_json(indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
