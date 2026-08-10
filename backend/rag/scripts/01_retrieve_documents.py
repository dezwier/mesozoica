"""Fetch Wikipedia sections and OpenAlex abstracts without database writes."""

from __future__ import annotations

import argparse
import os

from dotenv import load_dotenv

from mesozoica_ai.sources import OpenAlexSource, WikipediaSource


def main(argv: list[str] | None = None) -> int:
    """Run the source retrieval example."""
    parser = argparse.ArgumentParser()
    parser.add_argument("title", nargs="?", default="Triceratops")
    args = parser.parse_args(argv)
    load_dotenv()
    user_agent = os.environ["WIKIPEDIA_USER_AGENT"]
    with WikipediaSource(user_agent=user_agent) as wikipedia, OpenAlexSource(
        api_key=os.environ["OPENALEX_API_KEY"], user_agent=user_agent
    ) as openalex:
        documents = wikipedia.fetch(args.title) + openalex.search(args.title, limit=10)
    for document in documents:
        print(document.id, document.metadata.title, len(document.text))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
