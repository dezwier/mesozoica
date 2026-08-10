"""Fetch Wikipedia sections and OpenAlex abstracts."""

from __future__ import annotations

import argparse
import os

from dotenv import load_dotenv

from mesozoica_ai import retrieve_openalex, retrieve_wikipedia


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("title", nargs="?", default="Triceratops")
    args = parser.parse_args(argv)
    load_dotenv()
    user_agent = os.environ["WIKIPEDIA_USER_AGENT"]

    wikipedia = retrieve_wikipedia(args.title, user_agent=user_agent)
    openalex = retrieve_openalex(
        args.title,
        api_key=os.environ["OPENALEX_API_KEY"],
        user_agent=user_agent,
        limit=10,
    )
    for result in (wikipedia, openalex):
        for document in result.documents:
            print(result.source, document.id, document.metadata.title, len(document.text))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
