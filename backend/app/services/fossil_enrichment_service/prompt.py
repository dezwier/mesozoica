"""Build Gemini prompts for fossil enrichment."""

from __future__ import annotations

import json

from app.models.dinosaur_type import DinosaurType
from app.models.fossil import Fossil
from app.services.image_generation_service.fossil_json import fossil_to_enrichment_prompt_dict

_SYSTEM_INSTRUCTION = """You are a paleontology data assistant.
Read the fossil occurrence record and return ONLY valid JSON (no markdown, no explanations).
Every enum field must be one of the allowed values listed in the user prompt, including "unknown".
When the record clearly supports a value, choose the closest match. When evidence is weak or
absent, return "unknown" for that field — do not guess or invent values.
Do not infer anatomy, lithology, or preservation from taxon name alone.
PBDB catalog numbers, collection metadata, and geographic names are not evidence for classification.
The PBDB field research_group (often "vertebrate") refers to vertebrate paleontology — it is NOT
evidence for vertebrae bones. Never pick llm_subcategory=vertebrae from research_group or taxonomy.
Do not output llm_category — it is derived from llm_subcategory after your response."""

_USER_PREFIX = """Classify this fossil occurrence record into normalized museum-card fields.

Return a JSON object with exactly these keys:
{
  "llm_rock_type": "<sedimentary rock type>",
  "llm_subcategory": "<anatomical or trace type>",
  "llm_preservation_quality": "<preservation grade>",
  "llm_completeness": "<how complete the specimen is>",
  "llm_description": "<one catchy but truthful museum-card sentence, or null>"
}

Allowed values (all lowercase snake_case):

llm_rock_type — host rock / lithology:
  mudstone, shale, siltstone, sandstone, conglomerate, limestone, marl, chalk,
  claystone, coal, volcanic_ash, tuff, ironstone, phosphorite, evaporite, other, unknown
  Use lithology1, lithology2, lithdescript, lithadj1, stratcomments. Pick the closest
  listed type. Use "other" for a clearly stated but unlisted rock. If lithology is
  absent or ambiguous, use "unknown".

llm_subcategory — anatomical element or trace type
  Body fossils: skull, teeth, vertebrae, ribs_and_gastralia, pectoral_girdle,
    forelimbs, pelvic_girdle, hindlimbs, tail_structures, dermal_armour,
    skin_and_soft_tissue, eggs_and_embryos
  Trace fossils: footprints_and_trackways, burrows_and_nesting_traces,
    bite_marks_and_feeding_traces, coprolites, gastroliths, regurgitates
  Also allowed: unknown
  Use feed_pred_traces, component_comments, bioerosion, occurrence_comments,
  pres_mode, and record_type as primary evidence for trace fossils.
  Tooth marks, bite marks, feeding traces, and predation traces map to
  bite_marks_and_feeding_traces.
  Only choose vertebrae when vertebrae, cervical, dorsal, or caudal backbone elements
  are explicitly described for this occurrence. Do not use collection-level body-part
  summaries, research_group, taxonomy, or catalog numbers. If unclear, use "unknown".

llm_preservation_quality:
  exceptional, excellent, good, moderate, poor, very_poor, unknown
  Map PBDB preservation_quality when clearly equivalent; consider lagerstatten,
  preservation_comments, fragmentation. If unclear, use "unknown".

llm_completeness:
  nearly_complete, substantial, partial, fragmentary, isolated_element, trace_only, unknown
  When llm_subcategory is a trace type, prefer trace_only. Use occurrence_comments,
  pres_mode, feed_pred_traces, fragmentation, and preservation_comments. If unclear,
  use "unknown".

llm_description:
  One concise, engaging sentence summarizing what this fossil occurrence is
  (what was found, where/when if known, and why it matters). Use only facts
  supported by the record. Use null when the record lacks enough detail.

Rules:
- Do not include llm_category in your JSON — category (body vs trace) is derived from
  llm_subcategory after validation.
- Enum values must be lowercase snake_case strings from the allowed lists only.
- When evidence supports a value, use it; otherwise use "unknown".
- llm_description is normal prose (not snake_case).

Occurrence id: """


def build_enrichment_prompt(fossil: Fossil, *, dinosaur: DinosaurType) -> tuple[str, str]:
    """Return (system_instruction, user_prompt) for Gemini."""
    payload = fossil_to_enrichment_prompt_dict(fossil, dinosaur_name=dinosaur.name)
    payload["dinosaur_period"] = dinosaur.period
    payload["dinosaur_short_description"] = dinosaur.short_description
    user_prompt = (
        _USER_PREFIX
        + str(fossil.id)
        + "\n\n---\n\nFossil record JSON:\n\n"
        + json.dumps(payload, ensure_ascii=False)
    )
    return _SYSTEM_INSTRUCTION, user_prompt
