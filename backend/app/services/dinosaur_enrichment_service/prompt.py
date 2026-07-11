"""Build Gemini prompts for dinosaur enrichment."""

from __future__ import annotations

import json
from typing import Any

from app.models.dinosaur import Dinosaur
from app.services.dinosaur_enrichment_service.infobox_hints import extract_size_hints

_RECORD_DELIM = "\n\n---\n\nDinosaur record:\n\n"

_SYSTEM_INSTRUCTION = """You are a paleontology data assistant for a scientifically accurate museum game.
Return ONLY valid JSON (no markdown, no explanations).
Extract facts strictly from the provided record and full article HTML.
Use null for any field you cannot support from the source material — do not invent data."""

_STATIC_USER_PREFIX = """Extract structured dinosaur metadata from the record below.

Return a JSON object with exactly these keys:
{
  "length": "human-readable body length with metric units, or null if unknown",
  "mass": "human-readable body mass with metric units, or null if unknown",
  "location": "geographic region(s) where fossils were discovered, or null if unknown",
  "diet_type": "one of: herbivore, carnivore, omnivore, piscivore, insectivore, filter-feeder, unknown",
  "short_description": "one catchy but truthful sentence (30-280 chars) for a museum card"
}

Rules:
- length and mass: ALWAYS populate when length_hint, mass_hint, or the full article states a body size estimate.
  Search the entire article HTML (infobox rows, size/weight paragraphs, lead, description sections).
  Format with metric units (e.g. "12 m", "7 t", "4,500 kg"). Use null ONLY when no estimate exists anywhere.
- location: countries/regions/formation names from fossil discoveries; null if unknown
- diet_type: lowercase; use "unknown" only when diet is genuinely unclear
- short_description: exactly one sentence, engaging but factually accurate, no line breaks.
  Do not embed numeric measurements in the description — put those in length and mass instead."""


def build_enrichment_prompt(dinosaur: Dinosaur) -> tuple[str, str, dict[str, str]]:
    """Return (system_instruction, user_prompt, size_hints) for Gemini."""
    size_hints = extract_size_hints(dinosaur.article or "")
    record: dict[str, Any] = {
        "name": dinosaur.name,
        "period": dinosaur.period,
        "birth_ma": dinosaur.birth,
        "death_ma": dinosaur.death,
        "cladogram": dinosaur.cladogram,
        "diet_type_wikipedia": dinosaur.diet_type,
        "long_description": dinosaur.long_description,
        **size_hints,
        "article_html": dinosaur.article or "",
    }
    dynamic_suffix = json.dumps(record, ensure_ascii=False, indent=2)
    user_prompt = _STATIC_USER_PREFIX + _RECORD_DELIM + dynamic_suffix
    return _SYSTEM_INSTRUCTION, user_prompt, size_hints
