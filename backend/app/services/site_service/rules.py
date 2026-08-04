"""Deterministic normalization rules for site table rebuild."""

from __future__ import annotations

import re
from collections import Counter
from decimal import Decimal

from app.models.fossil import Fossil

ROCK_TYPES: tuple[str, ...] = (
    "sandstone",
    "mudstone",
    "claystone",
    "siltstone",
    "marl",
    "conglomerate",
    "shale",
    "limestone",
    "siliciclastic",
    "coal",
    "lime mudstone",
    "carbonate",
    "tuff",
    "phosphorite",
    "chalk",
    "lignite",
    "chert",
    "wackestone",
    "gravel",
)

NOT_REPORTED_LITHOLOGY = frozenset({"", "not reported"})

FORMATION_SKIP_PREFIXES = (
    "originally",
    "probably",
    "described",
    "near",
    "from layer",
    "both of which",
    "but could",
    "customarily",
    "the red beds",
    "this material",
    "equivalent to",
    "age described",
    "if ",
)

FORMATION_PATTERNS: tuple[re.Pattern[str], ...] = (
    re.compile(
        r"(?:referred to|assigned to|correlated with)\s+(?:the\s+)?"
        r"([A-ZÀ-ÖØ-öø-ÿ][\w\s'\-]{1,50}?)\s+(?:Formation|Fm\.?)\b",
        re.I,
    ),
    re.compile(
        r"(?:Member|Mbr\.?)\s+of\s+(?:the\s+)?([A-ZÀ-ÖØ-öø-ÿ][\w\s'\-]+?)\s+(?:Formation|Fm\.?)\b",
        re.I,
    ),
    re.compile(r"\b([A-ZÀ-ÖØ-öø-ÿ][\w\s'\-]{1,50}?)\s+Formation\b"),
    re.compile(r"\b([A-ZÀ-ÖØ-öø-ÿ][\w\s'\-]{1,50}?)\s+Fm\.?\b"),
    re.compile(r"\b([A-ZÀ-ÖØ-öø-ÿ][\w\s'\-]{1,50}?)\s+Group\b"),
    re.compile(r"[\"']([^\"']{3,80}?)\s*(?:Formation|Fm\.?|Group|Member)[\"']", re.I),
    re.compile(r"=\s*([A-ZÀ-ÖØ-öø-ÿ][\w\s'\-]+?)\s*(?:Formation|Fm\.?)\b"),
)


def _clean_formation_label(raw: str) -> str | None:
    text = " ".join(raw.split()).strip(" \"'.,;")
    if len(text) < 3 or len(text) > 255:
        return None
    lower = text.lower()
    if lower.startswith(FORMATION_SKIP_PREFIXES):
        return None
    if any(char.isdigit() for char in text[:8]):
        return None
    return text[:255]


def formation_from_text(text: str | None) -> str | None:
    """Extract a formation/group label from free-text stratigraphy comments."""
    if not text:
        return None
    for pattern in FORMATION_PATTERNS:
        matches = pattern.findall(text)
        for match in reversed(matches):
            cleaned = _clean_formation_label(match)
            if cleaned:
                return cleaned
    return None


def formation_for_fossil(fossil: Fossil) -> str | None:
    """Best formation label for one fossil row."""
    if fossil.geological_formation and fossil.geological_formation.strip():
        return fossil.geological_formation.strip()[:255]
    for field in (fossil.stratcomments, fossil.collection_name, fossil.collection_aka):
        found = formation_from_text(field)
        if found:
            return found
    return None


def formation_for_site(fossils: list[Fossil]) -> str | None:
    """Pick the most common formation across fossils at one site."""
    counts: Counter[str] = Counter()
    for fossil in fossils:
        formation = formation_for_fossil(fossil)
        if formation:
            counts[formation] += 1
    if not counts:
        return None
    return sorted(counts.items(), key=lambda item: (-item[1], item[0]))[0][0]


def _rock_type_from_text(text: str | None) -> str | None:
    if not text:
        return None
    lower = text.lower()
    for rock in ROCK_TYPES:
        if rock in lower:
            return rock
    return None


def rock_type_from_fossil(fossil: Fossil) -> str | None:
    """Derive a single rock type label from PBDB lithology, then llm_imp_rock_type."""
    if fossil.lithology1:
        cleaned = fossil.lithology1.strip().lower()
        if cleaned not in NOT_REPORTED_LITHOLOGY:
            return cleaned
    for field in (fossil.lithdescript, fossil.stratcomments, fossil.lithadj1):
        rock = _rock_type_from_text(field)
        if rock:
            return rock
    imp = (fossil.llm_imp_rock_type or "").strip().lower()
    if imp:
        return imp
    return None


def rock_type_for_site(fossils: list[Fossil]) -> str | None:
    """Pick the most common rock type across fossils at one site."""
    counts: Counter[str] = Counter()
    for fossil in fossils:
        rock = rock_type_from_fossil(fossil)
        if rock:
            counts[rock] += 1
    if not counts:
        return None
    return sorted(counts.items(), key=lambda item: (-item[1], item[0]))[0][0]


def ages_for_site(fossils: list[Fossil]) -> tuple[Decimal | None, Decimal | None]:
    """Derive site age span from member fossils (PBDB min_ma / max_ma bounds)."""
    min_ages = [fossil.min_age_ma for fossil in fossils if fossil.min_age_ma is not None]
    max_ages = [fossil.max_age_ma for fossil in fossils if fossil.max_age_ma is not None]
    if not min_ages and not max_ages:
        return None, None
    return (
        min(min_ages) if min_ages else None,
        max(max_ages) if max_ages else None,
    )


def period_for_ages(
    min_age_ma: Decimal | None,
    max_age_ma: Decimal | None,
) -> str | None:
    """
    Map site ages to triassic, jurassic, or cretaceous.

    Bounds (Ma): Triassic 252–201, Jurassic 201–145, Cretaceous 145–66.
    Uses the midpoint when both bounds are present.
    """
    if min_age_ma is None and max_age_ma is None:
        return None
    if min_age_ma is not None and max_age_ma is not None:
        mid = (min_age_ma + max_age_ma) / 2
    else:
        mid = min_age_ma if min_age_ma is not None else max_age_ma

    if mid > Decimal("201"):
        return "triassic"
    if mid > Decimal("145"):
        return "jurassic"
    if mid >= Decimal("66"):
        return "cretaceous"
    return None


# Full-period age bounds as (younger_ma, older_ma) for timeline display.
PERIOD_AGE_BOUNDS_MA: dict[str, tuple[float, float]] = {
    "triassic": (201.0, 252.0),
    "jurassic": (145.0, 201.0),
    "cretaceous": (66.0, 145.0),
}
