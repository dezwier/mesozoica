"""Build Gemini prompts for dinosaur enrichment."""

from __future__ import annotations

import json

from app.models.dinosaur import Dinosaur

_SYSTEM_INSTRUCTION = """You are a paleontology data assistant.
Read the Wikipedia article HTML and return ONLY valid JSON (no markdown, no explanations).
Use null for fields not supported by the article. Do not invent data."""

_USER_PREFIX = """Extract dinosaur metadata from the article below.

Return a JSON object with exactly these keys:
{
  "length": "human-readable body length with metric units, or null",
  "mass": "human-readable body mass with metric units, or null",
  "location": "geographic region(s) where fossils were discovered, or null",
  "diet_type": "herbivore, carnivore, omnivore, piscivore, insectivore, filter-feeder, unknown, or null",
  "short_description": "one catchy but truthful sentence for a museum card, or null"
}

Dinosaur name: """


def build_enrichment_prompt(dinosaur: Dinosaur) -> tuple[str, str]:
    """Return (system_instruction, user_prompt) for Gemini."""
    payload = {
        "name": dinosaur.name,
        "article_html": dinosaur.article or "",
    }
    user_prompt = (
        _USER_PREFIX
        + dinosaur.name
        + "\n\n---\n\nArticle HTML:\n\n"
        + json.dumps(payload, ensure_ascii=False)
    )
    return _SYSTEM_INSTRUCTION, user_prompt
