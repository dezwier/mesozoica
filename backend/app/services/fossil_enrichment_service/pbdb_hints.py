"""Infer LLM subcategory hints from explicit PBDB occurrence fields."""

from __future__ import annotations

from app.models.fossil import Fossil
from app.services.fossil_enrichment_service.validate import (
    TRACE_SUBCATEGORIES,
    UNKNOWN,
    FossilEnrichmentOutput,
    validate_llm_enrichment,
)

_TRACE_EVIDENCE_FIELDS: tuple[str, ...] = (
    "feed_pred_traces",
    "component_comments",
    "bioerosion",
    "occurrence_comments",
    "pres_mode",
    "composition",
    "record_type",
)

# Order matters: first match wins.
_SUBCATEGORY_PHRASES: tuple[tuple[str, frozenset[str]], ...] = (
    (
        "coprolites",
        frozenset({"coprolite", "coprolites", "feces", "faeces", "dung"}),
    ),
    (
        "gastroliths",
        frozenset({"gastrolith", "gastroliths", "stomach stone", "stomach stones"}),
    ),
    (
        "regurgitates",
        frozenset(
            {
                "regurgitate",
                "regurgitates",
                "gastric pellet",
                "gastric pellets",
                "owl pellet",
                "owl pellets",
            }
        ),
    ),
    (
        "footprints_and_trackways",
        frozenset(
            {
                "footprint",
                "footprints",
                "trackway",
                "trackways",
                "ichnite",
                "ichnites",
            }
        ),
    ),
    (
        "burrows_and_nesting_traces",
        frozenset({"burrow", "burrows", "nest trace", "nesting trace", "nesting"}),
    ),
    (
        "bite_marks_and_feeding_traces",
        frozenset(
            {
                "tooth mark",
                "tooth marks",
                "bite mark",
                "bite marks",
                "feeding trace",
                "feeding traces",
                "predation trace",
                "predation traces",
                "predatory trace",
                "predatory traces",
                "gnaw mark",
                "gnaw marks",
                "scrap mark",
                "scrap marks",
                "arthropod boring",
                "arthropod borings",
                "boring trace",
                "boring traces",
                "bioerosion",
                "drill hole",
                "drill holes",
            }
        ),
    ),
)


def _pbdb_trace_evidence_text(fossil: Fossil) -> str:
    parts: list[str] = []
    for field in _TRACE_EVIDENCE_FIELDS:
        value = getattr(fossil, field, None)
        if value:
            parts.append(str(value))
    return " ".join(parts).lower()


def infer_subcategory_from_pbdb(fossil: Fossil) -> str | None:
    """Return a trace subcategory when PBDB fields explicitly describe one."""
    text = _pbdb_trace_evidence_text(fossil)
    if not text.strip():
        return None

    for subcategory, phrases in _SUBCATEGORY_PHRASES:
        if subcategory not in TRACE_SUBCATEGORIES:
            continue
        if any(phrase in text for phrase in phrases):
            return subcategory

    if "trace fossil" in text or text.strip() == "trace":
        return None

    return None


def apply_pbdb_hints(
    fossil: Fossil,
    validated: FossilEnrichmentOutput,
) -> FossilEnrichmentOutput:
    """Fill unknown LLM subcategory from explicit PBDB trace evidence."""
    if validated.llm_subcategory != UNKNOWN:
        return validated

    inferred = infer_subcategory_from_pbdb(fossil)
    if inferred is None:
        return validated

    payload = validated.model_dump()
    payload["llm_subcategory"] = inferred
    if payload.get("llm_completeness") == UNKNOWN:
        payload["llm_completeness"] = "trace_only"
    return validate_llm_enrichment(payload)
