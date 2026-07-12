"""Imagen prompt builders for dinosaur and fossil card images."""

from __future__ import annotations

import json
from typing import Any

_DINOSAUR_INSTRUCTIONS = """Generate a 3:4 image of the following dinosaur: {name}
The image must have these features - according to latest science, be as truthful as possible (considering anatomy, color, surroundings, timing, etc) - within what is scientifically correct, it can show something interesting about the dinosaur itself, or their surrounding. Be correct however, don't make stuff up - look like an iphone photograph, so very realistic (NOT cartoonic) - in terms of color tone, it should slightly have the iphone filter 'dramatic warm' - no other special filtering, no vignette, no special editing otherwise - have no borders, no text, or other elements other than the photo itself
- consider the following wikipedia article as context
{article}"""

_FOSSIL_INSTRUCTIONS = """Generate a 3:4 portrait photo of a dinosaur fossil at an active field excavation site. Documentary iPhone photo with slight 'dramatic warm' tone. Real paleontology, NOT cartoon, NOT CGI.

Show imperfect in-situ field documentation:
- fossil partially exposed in natural rock/sediment matrix, still embedded or freshly uncovered
- dusty dig site, uneven lighting, field tools or tarps in background optional
- authentic wear: cracks, broken edges, matrix clinging to bone, irregular exposure
- depict the specific body parts or trace type listed below when provided
- do NOT beautify, over-restore, or museum-prepare the specimen

Avoid entirely: lab bench, glass case, mounted skeleton, polished specimen, studio lighting, stock-photo perfection.

Depict this occurrence:
{preservation_brief}

Image-relevant occurrence data:
{fossil_json}"""

_PRESERVATION_QUALITY_GUIDANCE: dict[str, str] = {
    "poor": "Visibly poor preservation: heavy weathering, erosion, missing pieces, crumbling matrix.",
    "medium": "Moderate preservation: partial exposure, worn surfaces, some breakage, mixed with matrix.",
    "good": "Better preservation but still in field matrix — not cleaned, mounted, or lab-prepped.",
}

_PRES_MODE_GUIDANCE: dict[str, str] = {
    "body": "Body fossil: show the listed bone/tooth elements partially exposed in rock.",
    "trace": "Trace fossil: show impression, track, burrow, or ichnofossil in sediment.",
}

_PERIOD_CONTEXT: dict[str, str] = {
    "triassic": (
        "Triassic period (~252–201 million years ago): arid to semi-arid early Mesozoic "
        "landscapes, sparse conifers and ferns, red beds and evaporites common."
    ),
    "jurassic": (
        "Jurassic period (~201–145 million years ago): warm humid climates, lush conifers "
        "and cycads, coastal plains and shallow inland seas."
    ),
    "cretaceous": (
        "Cretaceous period (~145–66 million years ago): varied Mesozoic landscapes, "
        "angiosperms emerging, chalk, sandstone, and claystone formations common."
    ),
}

_SITE_TYPE_INSTRUCTIONS = """Generate a 3:4 portrait photo of a natural geological field outcrop at a paleontological dig site. Documentary iPhone photo with slight 'dramatic warm' tone. Real geology and landscape, NOT cartoon, NOT CGI.

Primary subject — rock type (most important):
- show {rock_type} clearly as the dominant exposed lithology: bedding, texture, color, and weathering typical of this rock type in the field
- natural eroded cliff face, hillside cut, or badlands outcrop where a fossil site would realistically occur
- dusty field setting, uneven daylight, authentic geological strata

Imperfect, scrappy field look (important — do NOT make it too clean):
- weathered, irregular exposure: cracked surfaces, loose talus, rubble at the base, dust, lichen, partial erosion
- uneven lighting, slightly blown highlights or muddy shadows — casual handheld iPhone snapshot, not a polished landscape photo
- do NOT beautify, over-sharpen, or CGI-polish the outcrop; avoid pristine cliff faces and hyper-saturated colors

Geological period (secondary context):
- {period_context}

Hard constraints:
- no text, labels, signs, maps, or watermarks
- no people, vehicles, tools, tarps, tents, or excavation equipment
- no borders, frames, or graphic overlays
- only nature: rock, sediment, sky, and period-appropriate vegetation if any

Avoid: museum displays, polished rock slabs, studio backdrops, stock-photo perfection, overly clean or manicured scenery."""


def build_dinosaur_image_prompt(name: str, article_text: str) -> str:
    """Build Imagen prompt for a dinosaur genus card image."""
    return _DINOSAUR_INSTRUCTIONS.format(name=name.strip(), article=article_text.strip())


def build_fossil_preservation_brief(fossil_data: dict[str, Any]) -> str:
    """Human-readable brief focused on what the image should show."""
    lines: list[str] = []

    dino_name = fossil_data.get("dinosaur_name")
    if dino_name:
        lines.append(f"- Dinosaur: {dino_name}")

    identified = fossil_data.get("identified_name")
    if identified and identified != dino_name:
        lines.append(f"- Identified as: {identified}")

    pres_mode = _normalize_key(fossil_data.get("pres_mode"))
    if pres_mode:
        guidance = _PRES_MODE_GUIDANCE.get(pres_mode, "")
        suffix = f" — {guidance}" if guidance else ""
        lines.append(f"- Fossil type ({pres_mode}){suffix}")

    for label, key in (
        ("Show these body parts", "common_body_parts"),
        ("Rare elements", "rare_body_parts"),
        ("Articulation", "articulated_parts"),
        ("Associated elements", "associated_parts"),
        ("Trace/feeding marks", "feed_pred_traces"),
    ):
        value = fossil_data.get(key)
        if value:
            lines.append(f"- {label}: {value}")

    for key, prefix in (
        ("component_comments", "Collection notes"),
        ("occurrence_comments", "Occurrence notes"),
    ):
        value = fossil_data.get(key)
        if value:
            lines.append(f"- {prefix}: {value}")

    quality = _normalize_key(fossil_data.get("preservation_quality"))
    if quality:
        guidance = _PRESERVATION_QUALITY_GUIDANCE.get(quality, "")
        suffix = f" — {guidance}" if guidance else ""
        lines.append(f"- Preservation ({quality}){suffix}")

    for field_name, hint in (
        ("fragmentation", "show broken/irregular edges"),
        ("composition", "mineral composition visible in matrix"),
        ("architecture", "taphonomic texture"),
        ("size_classes", None),
    ):
        value = fossil_data.get(field_name)
        if value:
            suffix = f" ({hint})" if hint else ""
            label = field_name.replace("_", " ").capitalize()
            lines.append(f"- {label}: {value}{suffix}")

    formation = fossil_data.get("geological_formation")
    early_interval = fossil_data.get("early_interval")
    min_age = fossil_data.get("min_age_ma")
    max_age = fossil_data.get("max_age_ma")
    if formation or early_interval or min_age is not None or max_age is not None:
        age_bits = []
        if early_interval:
            age_bits.append(str(early_interval))
        if min_age is not None or max_age is not None:
            age_bits.append(f"{min_age}–{max_age} Ma")
        age_text = ", ".join(age_bits)
        formation_text = formation or "unspecified formation"
        lines.append(f"- Stratigraphy: {formation_text}" + (f" ({age_text})" if age_text else ""))

    lith_bits = [
        fossil_data.get("lithdescript"),
        fossil_data.get("lithology1"),
        fossil_data.get("lithadj1"),
    ]
    lith_text = "; ".join(str(bit) for bit in lith_bits if bit)
    if lith_text:
        lines.append(f"- Rock/matrix: {lith_text}")

    if fossil_data.get("stratcomments"):
        lines.append(f"- Stratigraphy notes: {fossil_data['stratcomments']}")

    env_bits = [
        fossil_data.get("environment"),
        fossil_data.get("country_code"),
        fossil_data.get("state"),
    ]
    env_text = ", ".join(str(bit) for bit in env_bits if bit)
    if env_text:
        lines.append(f"- Field setting: {env_text}")

    if fossil_data.get("geogcomments"):
        lines.append(f"- Site: {fossil_data['geogcomments']}")

    collection = fossil_data.get("collection_name") or fossil_data.get("collection_aka")
    if collection:
        lines.append(f"- Dig/collection: {collection}")

    if not lines:
        lines.append(
            "- Partial in-situ exposure in natural matrix; imperfect field documentation only."
        )

    return "\n".join(lines)


def build_fossil_image_prompt(fossil_data: dict[str, Any]) -> str:
    """Build Imagen prompt for a fossil occurrence card image."""
    preservation_brief = build_fossil_preservation_brief(fossil_data)
    fossil_json = json.dumps(fossil_data, ensure_ascii=False, separators=(",", ":"))
    return _FOSSIL_INSTRUCTIONS.format(
        preservation_brief=preservation_brief,
        fossil_json=fossil_json,
    )


def build_site_type_image_prompt(*, period: str, rock_type: str) -> str:
    """Build Imagen prompt for a site-type card image (field outcrop by lithology + period)."""
    period_key = _normalize_key(period)
    period_context = _PERIOD_CONTEXT.get(
        period_key,
        f"{period.strip().capitalize()} period: Mesozoic geological landscape.",
    )
    return _SITE_TYPE_INSTRUCTIONS.format(
        rock_type=rock_type.strip(),
        period_context=period_context,
    )


def _normalize_key(value: Any) -> str:
    if value is None:
        return ""
    return str(value).strip().lower()
