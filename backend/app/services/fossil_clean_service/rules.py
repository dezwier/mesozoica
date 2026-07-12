"""Deterministic normalization rules for fossil clean tables."""

from __future__ import annotations

import re
from collections import Counter
from decimal import Decimal

from app.models.fossil import Fossil

TRACE_TYPES = frozenset({"footprint", "tooth_mark", "coprolite", "boring"})

BODY_BONE_NAMES = frozenset(
    {
        "femur",
        "humerus",
        "ulna",
        "tibia",
        "fibula",
        "radius",
        "ilium",
        "ischium",
        "pubis",
        "scapula",
        "mandible",
        "rib",
        "metatarsal",
        "pelvis",
    }
)

TOKEN_ALIASES: dict[str, str] = {
    "teeth": "tooth",
    "tooth": "tooth",
    "partial skeletons": "skeleton",
    "skeletons": "skeleton",
    "skeleton": "skeleton",
    "partial skulls": "skull",
    "skulls": "skull",
    "skull": "skull",
    "vertebrae": "vertebra",
    "vertebra": "vertebra",
    "limb elements": "limb",
    "postcrania": "limb",
    "postcranial": "limb",
    "limb": "limb",
    "partial shells": "shell",
    "partialshells": "shell",
    "eggs": "egg",
    "egg": "egg",
    "osteoderms": "osteoderm",
    "osteoderm": "osteoderm",
    "mandibles": "mandible",
    "footprints": "footprint",
    "footprint": "footprint",
    "tooth marks": "tooth_mark",
    "arthropod boring": "boring",
    "coprolite": "coprolite",
    "coprolites": "coprolite",
    "dermal scales": "scale",
    "dermalscales": "scale",
    "dermal spine": "osteoderm",
    "otoliths": "otolith",
    "metatarsus": "metatarsal",
}

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

YEAR_RE = re.compile(r"\b(1[89]\d{2}|20\d{2})\b")

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

FRAGMENTATION_QUALITY = {
    "none": "good",
    "occasional": "medium",
    "frequent": "poor",
    "extreme": "very poor",
}

ARCHITECTURE_QUALITY = {
    "compact or dense": "good",
}

PRES_MODE_SUBCATEGORY = {
    "mold/impression": "impression",
    "cast": "cast",
    "concretion": "concretion",
    "soft parts": "soft_tissue",
    "adpression": "adpression",
    "coprolite": "coprolite",
    "permineralized": "permineralized",
    "charcoalification": "charcoal",
}

ARTICULATED_SUBCATEGORY = {
    "some": "partial_skeleton",
    "many": "skeleton",
}

COMMENT_KEYWORD_PATTERNS: tuple[tuple[re.Pattern[str], str], ...] = (
    (re.compile(r"\btooth\s+marks?\b", re.I), "tooth_mark"),
    (re.compile(r"\barthropod\s+boring\b", re.I), "boring"),
    (re.compile(r"\bcoprolit(?:e|es)\b", re.I), "coprolite"),
    (re.compile(r"\bfootprints?\b", re.I), "footprint"),
    (re.compile(r"\b(?:anterior\s+)?caudal\s+vertebra", re.I), "vertebra"),
    (re.compile(r"\bdorsal\s+vertebra", re.I), "vertebra"),
    (re.compile(r"\bpostcranial\b", re.I), "limb"),
    (re.compile(r"\bfemur\b", re.I), "femur"),
    (re.compile(r"\bhumerus\b", re.I), "humerus"),
    (re.compile(r"\bulna\b", re.I), "ulna"),
    (re.compile(r"\btibia\b", re.I), "tibia"),
    (re.compile(r"\bfibula\b", re.I), "fibula"),
    (re.compile(r"\bradius\b", re.I), "radius"),
    (re.compile(r"\bilium\b", re.I), "ilium"),
    (re.compile(r"\bischium\b", re.I), "ischium"),
    (re.compile(r"\bpubis\b", re.I), "pubis"),
    (re.compile(r"\bpubes\b", re.I), "pubis"),
    (re.compile(r"\bscapula\b", re.I), "scapula"),
    (re.compile(r"\bmandible\b", re.I), "mandible"),
    (re.compile(r"\bmaxillar(?:y|ies)\b", re.I), "mandible"),
    (re.compile(r"\bdentary\b", re.I), "mandible"),
    (re.compile(r"\bmetatarsal\b", re.I), "metatarsal"),
    (re.compile(r"\bmetatarsus\b", re.I), "metatarsal"),
    (re.compile(r"\bvertebra(?:e)?\b", re.I), "vertebra"),
    (re.compile(r"\bskull\b", re.I), "skull"),
    (re.compile(r"\btooth\b", re.I), "tooth"),
    (re.compile(r"\bteeth\b", re.I), "tooth"),
    (re.compile(r"\brib(?:s)?\b", re.I), "rib"),
    (re.compile(r"\beggs?\b", re.I), "egg"),
    (re.compile(r"\bskeleton\b", re.I), "skeleton"),
    (re.compile(r"\bpelvis\b", re.I), "pelvis"),
    (re.compile(r"\bpremaxilla(?:ry)?\b", re.I), "skull"),
    (re.compile(r"\bsquamosal\b", re.I), "skull"),
    (re.compile(r"\bparietal\b", re.I), "parietal"),
    (re.compile(r"\bdermal\s+spine\b", re.I), "osteoderm"),
    (re.compile(r"\bpartial\s+skull\b", re.I), "skull"),
    (re.compile(r"\bpartial\s+skeleton\b", re.I), "skeleton"),
)


def fossil_type(pres_mode: str | None) -> str:
    """Return ``body`` or ``trace`` from PBDB preservation mode."""
    if not pres_mode:
        return "body"
    tokens = {part.strip().lower() for part in pres_mode.split(",") if part.strip()}
    has_body = "body" in tokens
    has_trace = "trace" in tokens or "coprolite" in tokens
    if has_trace and not has_body:
        return "trace"
    return "body"


def fossil_name(
    *,
    identified_name: str | None,
    accepted_name: str | None,
    genus: str | None,
) -> str | None:
    """Best display name for a fossil occurrence."""
    for value in (identified_name, accepted_name, genus):
        if value and value.strip():
            return value.strip()[:255]
    return None


def _normalize_token(raw: str) -> str | None:
    cleaned = " ".join(raw.strip().lower().split())
    if not cleaned:
        return None
    if cleaned in BODY_BONE_NAMES:
        return cleaned
    if cleaned in TOKEN_ALIASES:
        return TOKEN_ALIASES[cleaned]
    compact = cleaned.replace(" ", "")
    if compact in TOKEN_ALIASES:
        return TOKEN_ALIASES[compact]
    return None


def _split_field_tokens(value: str | None) -> list[str]:
    if not value:
        return []
    return [part.strip() for part in value.split(",") if part.strip()]


def _tokens_from_comments(*texts: str | None) -> set[str]:
    found: set[str] = set()
    for text in texts:
        if not text:
            continue
        for pattern, normalized in COMMENT_KEYWORD_PATTERNS:
            if pattern.search(text):
                found.add(normalized)
    return found


def _tokens_from_pres_mode(pres_mode: str | None) -> set[str]:
    if not pres_mode:
        return set()
    tokens: set[str] = set()
    for part in pres_mode.split(","):
        key = part.strip().lower()
        if key.startswith("replaced with "):
            tokens.add("mineralized")
            continue
        mapped = PRES_MODE_SUBCATEGORY.get(key)
        if mapped:
            tokens.add(mapped)
    return tokens


def sub_category(
    *,
    fossil_kind: str,
    common_body_parts: str | None,
    rare_body_parts: str | None,
    associated_parts: str | None,
    feed_pred_traces: str | None,
    occurrence_comments: str | None,
    component_comments: str | None,
    pres_mode: str | None = None,
    articulated_parts: str | None = None,
) -> str | None:
    """Return comma-separated normalized body/trace part labels."""
    categories: set[str] = set()

    for field in (common_body_parts, rare_body_parts, associated_parts):
        for token in _split_field_tokens(field):
            normalized = _normalize_token(token)
            if normalized:
                categories.add(normalized)

    trace_tokens: set[str] = set()
    for token in _split_field_tokens(feed_pred_traces):
        normalized = _normalize_token(token)
        if normalized:
            trace_tokens.add(normalized)

    comment_tokens = _tokens_from_comments(occurrence_comments, component_comments)

    if fossil_kind == "trace":
        categories.update(trace_tokens)
        categories.update(comment_tokens)
    else:
        categories.update(token for token in comment_tokens if token not in TRACE_TYPES)
        categories.update(token for token in trace_tokens if token in TRACE_TYPES)

    if articulated_parts:
        mapped = ARTICULATED_SUBCATEGORY.get(articulated_parts.strip().lower())
        if mapped:
            categories.add(mapped)

    if not categories:
        categories.update(_tokens_from_pres_mode(pres_mode))
    else:
        categories.update(_tokens_from_pres_mode(pres_mode) & TRACE_TYPES)

    if not categories:
        return None
    return ",".join(sorted(categories))


def parse_collection_years(collection_dates: str | None) -> tuple[int | None, int | None]:
    """Extract earliest and latest collection year from PBDB free-text dates."""
    if not collection_dates:
        return None, None
    normalized = collection_dates.replace("–", "-").replace("—", "-")
    years = [int(match) for match in YEAR_RE.findall(normalized)]
    if not years:
        return None, None
    return min(years), max(years)


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
    """Derive a single rock type label from all available lithology fields."""
    if fossil.lithology1:
        cleaned = fossil.lithology1.strip().lower()
        if cleaned not in NOT_REPORTED_LITHOLOGY:
            return cleaned
    for field in (fossil.lithdescript, fossil.stratcomments, fossil.lithadj1):
        rock = _rock_type_from_text(field)
        if rock:
            return rock
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


def clean_preservation_quality(value: str | None) -> str | None:
    if not value:
        return None
    cleaned = value.strip().lower()
    return cleaned or None


def infer_preservation_quality(
    *,
    preservation_quality: str | None,
    fragmentation: str | None,
    architecture: str | None,
) -> str | None:
    """Map explicit PBDB quality or infer from fragmentation/architecture."""
    direct = clean_preservation_quality(preservation_quality)
    if direct:
        return direct
    if fragmentation:
        mapped = FRAGMENTATION_QUALITY.get(fragmentation.strip().lower())
        if mapped:
            return mapped
    if architecture:
        mapped = ARCHITECTURE_QUALITY.get(architecture.strip().lower())
        if mapped:
            return mapped
    return None


# Backwards-compatible alias used in tests
def rock_type_from_lithology(lithology1: str | None, lithdescript: str | None) -> str | None:
    if lithology1:
        cleaned = lithology1.strip().lower()
        if cleaned not in NOT_REPORTED_LITHOLOGY:
            return cleaned
    return _rock_type_from_text(lithdescript)


COMMENT_MAX_LEN = 10_000

# (label, fossil attribute name) in priority order
FOSSIL_COMMENT_FIELDS: tuple[tuple[str, str], ...] = (
    ("Occurrence", "occurrence_comments"),
    ("Component", "component_comments"),
    ("Description", "description"),
    ("Geography", "geogcomments"),
    ("Stratigraphy", "stratcomments"),
    ("Lithology", "lithdescript"),
    ("Collection", "collection_name"),
    ("Collection alias", "collection_aka"),
    ("Collection dates", "collection_dates"),
    ("Collection methods", "collection_methods"),
    ("Collectors", "collectors"),
    ("Museum", "museum"),
    ("Research group", "research_group"),
    ("Environment", "environment"),
    ("Taxon environment", "taxon_environment"),
    ("Life habit", "life_habit"),
    ("Diet", "diet"),
    ("Motility", "motility"),
    ("Reproduction", "reproduction"),
    ("Ontogeny", "ontogeny"),
    ("Preservation mode", "pres_mode"),
    ("Composition", "composition"),
    ("Architecture", "architecture"),
    ("Fragmentation", "fragmentation"),
    ("Size class", "size_classes"),
    ("Concentration", "concentration"),
    ("Early interval", "early_interval"),
    ("Taxon attribution", "accepted_attr"),
    ("Artifacts", "artifacts"),
    ("Feeding traces", "feed_pred_traces"),
)


def _normalize_comment_text(value: str) -> str:
    return " ".join(value.split()).strip()


def _join_unique_texts(*values: str | None) -> str | None:
    parts: list[str] = []
    seen: set[str] = set()
    for value in values:
        if not value:
            continue
        cleaned = _normalize_comment_text(value)
        if not cleaned:
            continue
        key = cleaned.casefold()
        if key in seen:
            continue
        seen.add(key)
        parts.append(cleaned)
    if not parts:
        return None
    return "; ".join(parts)


def fossil_comment(fossil: Fossil) -> str | None:
    """Concatenate informative free-text fossil fields into one narrative."""
    sections: list[str] = []
    seen_values: set[str] = set()

    def add_section(label: str, value: str | None) -> None:
        if not value:
            return
        cleaned = _normalize_comment_text(value)
        if not cleaned:
            return
        key = cleaned.casefold()
        if key in seen_values:
            return
        seen_values.add(key)
        sections.append(f"{label}: {cleaned}")

    for label, attr in FOSSIL_COMMENT_FIELDS:
        add_section(label, getattr(fossil, attr, None))

    body_parts = _join_unique_texts(
        fossil.common_body_parts,
        fossil.rare_body_parts,
        fossil.associated_parts,
        fossil.articulated_parts,
    )
    add_section("Body parts", body_parts)

    if not sections:
        return None

    text = " | ".join(sections)
    if len(text) > COMMENT_MAX_LEN:
        return text[: COMMENT_MAX_LEN - 3].rstrip() + "..."
    return text
