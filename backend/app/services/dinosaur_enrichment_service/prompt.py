"""Build Gemini prompts for dinosaur enrichment."""

from __future__ import annotations

import json

from app.models.dinosaur_type import DinosaurType

_SYSTEM_INSTRUCTION = """You are a paleontology data assistant.
Read the Wikipedia article HTML and return ONLY valid JSON (no markdown, no explanations).
Use null for any field the article does not clearly state. Do not invent or estimate data."""

_USER_PREFIX = """Extract dinosaur metadata from the article below.

Return a JSON object with exactly these keys:
{
  "length": "body length in metric units, or null",
  "mass": "body mass in metric units, or null",
  "location": "geographic region(s) where fossils were discovered, or null",
  "diet_type": "herbivore, carnivore, omnivore, piscivore, insectivore, filter-feeder, unknown, or null",
  "short_description": "one catchy but truthful sentence for a museum card, or null"
}

Formatting rules for length and mass:
- length: use cm or m only (e.g. "150 cm", "12 m", "5-10 m"). Convert from feet, inches, etc.
- mass: use kg or t only (e.g. "700 kg", "7 t", "5-10 t"). Convert from pounds, short tons, etc.
- Ranges are allowed when the article gives a range (e.g. "5-10 t", "8-12 m").
- Use null when the article does not clearly state a body length or mass. Do not guess.

Dinosaur name: """


def build_enrichment_prompt(dinosaur: DinosaurType) -> tuple[str, str]:
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
