"""Minimal source retrieval example; no Azure or database writes."""

import os

from dotenv import load_dotenv

from mesozoica_ai.sources import OpenAlexSource, WikipediaSource

load_dotenv()
name = "Triceratops"
user_agent = os.environ.get("WIKIPEDIA_USER_AGENT", "MesozoicaBot/1.0 (contact@example.com)")

documents = WikipediaSource(user_agent=user_agent).fetch(name)
documents += OpenAlexSource(
    api_key=os.environ["OPENALEX_API_KEY"], user_agent=user_agent
).search(name, limit=10)

for document in documents:
    print(document.id, document.metadata.get("title"), len(document.text))
