"""Build Gemini prompts for fossil enrichment."""

from __future__ import annotations

import json

from app.models.dinosaur import Dinosaur
from app.models.fossil import Fossil
from app.services.image_generation_service.fossil_json import fossil_to_prompt_dict

_SYSTEM_INSTRUCTION = """You are a paleontology data assistant.
Read the fossil occurrence record and return ONLY valid JSON (no markdown, no explanations).
Every enum field must be one of the allowed values listed in the user prompt — never "unknown",
null, or any value outside those lists.
When the record clearly supports a value, choose the closest match. When evidence is weak or
absent, pick uniformly at random from that field's allowed values.
Do not infer anatomy, lithology, or preservation from taxon name alone.
PBDB catalog numbers, collection metadata, and geographic names are not evidence for classification."""

_USER_PREFIX = """Classify this fossil occurrence record into normalized museum-card fields.

Return a JSON object with exactly these keys:
{
  "llm_rock_type": "<sedimentary rock type>",
  "llm_category": "<body_fossil | trace_fossil>",
  "llm_subcategory": "<anatomical or trace type>",
  "llm_preservation_quality": "<preservation grade>",
  "llm_completeness": "<how complete the specimen is>",
  "llm_description": "<one catchy but truthful museum-card sentence, or null>"
}

Allowed values (all lowercase snake_case):

llm_rock_type — host rock / lithology:
  mudstone, shale, siltstone, sandstone, conglomerate, limestone, marl, chalk,
  claystone, coal, volcanic_ash, tuff, ironstone, phosphorite, evaporite, other
  Use lithology1, lithology2, lithdescript, lithadj1, stratcomments. Pick the closest
  listed type. Use "other" for a clearly stated but unlisted rock. If lithology is
  absent or ambiguous, pick randomly from this list.

llm_category:
  body_fossil, trace_fossil
  If category is unclear, pick randomly between the two.

llm_subcategory — must match llm_category
  Body fossils: skull, teeth, vertebrae, ribs_and_gastralia, pectoral_girdle,
    forelimbs, pelvic_girdle, hindlimbs, tail_structures, dermal_armour,
    skin_and_soft_tissue, eggs_and_embryos
  Trace fossils: footprints_and_trackways, burrows_and_nesting_traces,
    bite_marks_and_feeding_traces, coprolites, gastroliths, regurgitates
  Pick from the list that matches llm_category. If unclear, pick randomly from that list.

llm_preservation_quality:
  exceptional, excellent, good, moderate, poor, very_poor
  Map PBDB preservation_quality when clearly equivalent; consider lagerstatten,
  preservation_comments, fragmentation. If unclear, pick randomly from this list.

llm_completeness:
  nearly_complete, substantial, partial, fragmentary, isolated_element, trace_only
  When llm_category is trace_fossil, prefer trace_only. Use articulated_parts,
  common_body_parts, fragmentation, collection_coverage, and comments. If unclear,
  pick randomly from this list.

llm_description:
  One concise, engaging sentence summarizing what this fossil occurrence is
  (what was found, where/when if known, and why it matters). Use only facts
  supported by the record. Use null when the record lacks enough detail.

Rules:
- llm_subcategory must be consistent with llm_category (body vs trace).
- Enum values must be lowercase snake_case strings from the allowed lists only.
  Never use "unknown", null, "not reported", "not specified", or similar.
- When evidence supports a value, use it; otherwise pick uniformly at random from
  that field's allowed values.
- llm_description is normal prose (not snake_case).

Occurrence id: """


def build_enrichment_prompt(fossil: Fossil, *, dinosaur: Dinosaur) -> tuple[str, str]:
    """Return (system_instruction, user_prompt) for Gemini."""
    payload = fossil_to_prompt_dict(fossil, dinosaur_name=dinosaur.name)
    payload["dinosaur_period"] = dinosaur.period
    payload["dinosaur_short_description"] = dinosaur.short_description
    user_prompt = (
        _USER_PREFIX
        + str(fossil.id)
        + "\n\n---\n\nFossil record JSON:\n\n"
        + json.dumps(payload, ensure_ascii=False)
    )
    return _SYSTEM_INSTRUCTION, user_prompt
