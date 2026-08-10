"""Fetch Wikipedia sections and OpenAlex abstracts for one title."""

import os

from dotenv import load_dotenv

from mesozoica_ai import retrieve_openalex, retrieve_wikipedia

load_dotenv()

TITLE = "Triceratops"
USER_AGENT = os.environ["WIKIPEDIA_USER_AGENT"]

wikipedia = retrieve_wikipedia(TITLE, user_agent=USER_AGENT)
openalex = retrieve_openalex(
    TITLE,
    api_key=os.environ["OPENALEX_API_KEY"],
    user_agent=USER_AGENT,
)

for source, documents in (("wikipedia", wikipedia), ("openalex", openalex)):
    for document in documents:
        print(source, document.id, document.metadata.title, len(document.text))
