"""Imagen prompt builders for dinosaur and fossil card images."""

from __future__ import annotations

from typing import Any

_DINOSAUR_INSTRUCTIONS = """Generate a 3:4 image of the following dinosaur: {name}
The image must have these features - according to latest science, be as truthful as possible (considering anatomy, color, surroundings, timing, etc) - within what is scientifically correct, it can show something interesting about the dinosaur itself, or their surrounding. Be correct however, don't make stuff up - look like an iphone photograph, so very realistic (NOT cartoonic) - in terms of color tone, it should slightly have the iphone filter 'dramatic warm' - no other special filtering, no vignette, no special editing otherwise - have no borders, no text, or other elements other than the photo itself
- consider the following wikipedia article as context
{article}"""

_FOSSIL_INSTRUCTIONS = """Generate a 3:4 portrait photo of a {dinosaur} fossil at an active field excavation site.
The dinosaur genus is the primary subject — depict anatomy, proportions, and bone texture consistent with that genus.

Documentary iPhone photograph with slight 'dramatic warm' color tone. Real paleontology, NOT cartoon, NOT CGI.
No borders, no text, no watermarks, no vignette — only the photo itself.

Show imperfect in-situ field documentation:
- fossil partially exposed in natural rock/sediment matrix, still embedded or freshly uncovered
- dusty dig site, uneven daylight, casual handheld framing
- authentic wear: cracks, broken edges, matrix clinging to bone, irregular exposure
- do NOT beautify, over-restore, or museum-prepare the specimen

Avoid entirely: lab bench, glass case, mounted skeleton, polished specimen, studio lighting, stock-photo perfection.

Depict this occurrence using ONLY the specification below. Every field is required — show a realistic in-situ fossil of this dinosaur genus with the stated host rock, fossil type, element or trace, completeness, and preservation quality all visible together:
{spec_brief}"""

_LLM_CATEGORY_GUIDANCE: dict[str, str] = {
    "body": "Body fossil: show the listed anatomical element partially exposed in rock.",
    "trace": "Trace fossil: show impression, track, burrow, or ichnofossil in sediment.",
    "body_fossil": "Body fossil: show the listed anatomical element partially exposed in rock.",
    "trace_fossil": "Trace fossil: show impression, track, burrow, or ichnofossil in sediment.",
}

_LLM_QUALITY_GUIDANCE: dict[str, str] = {
    "exceptional": "Exceptional preservation with fine surface detail still visible in the matrix.",
    "excellent": "Excellent preservation: clear bone or trace definition with limited damage.",
    "good": "Good preservation: recognizable form with some wear and matrix attachment.",
    "moderate": "Moderate preservation: partial exposure, worn surfaces, and some breakage.",
    "poor": "Poor preservation: heavy weathering, erosion, missing pieces, crumbling matrix.",
    "very_poor": "Very poor preservation: heavily fragmented, eroded, or barely recognizable remains.",
}

_LLM_COMPLETENESS_GUIDANCE: dict[str, str] = {
    "nearly_complete": "Nearly complete specimen: most of the element is present and connected.",
    "substantial": "Substantial remains: a large portion of the element is exposed.",
    "partial": "Partial remains: roughly half or less of the element is visible.",
    "fragmentary": "Fragmentary remains: broken pieces with irregular edges.",
    "isolated_element": "Isolated element: a single bone, tooth, or small part on its own.",
    "trace_only": "Trace only: impression or mark in sediment without body fossil bone.",
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
    """Human-readable brief from imputed LLM fields for fossil image prompts."""
    lines: list[str] = []

    dinosaur_id = fossil_data.get("dinosaur_id")
    if dinosaur_id is not None:
        lines.append(f"- Dinosaur catalog id: {dinosaur_id}")

    rock_type = fossil_data.get("llm_imp_rock_type")
    if rock_type:
        lines.append(
            f"- Host rock / matrix (required): {str(rock_type).replace('_', ' ')}"
        )

    category = _normalize_key(fossil_data.get("llm_imp_category"))
    if category:
        guidance = _LLM_CATEGORY_GUIDANCE.get(category, "")
        suffix = f" — {guidance}" if guidance else ""
        lines.append(f"- Fossil type (required: {category}){suffix}")

    subcategory = fossil_data.get("llm_imp_subcategory")
    if subcategory:
        lines.append(
            f"- Element / trace type (required): {str(subcategory).replace('_', ' ')}"
        )

    completeness = _normalize_key(fossil_data.get("llm_imp_completeness"))
    if completeness:
        guidance = _LLM_COMPLETENESS_GUIDANCE.get(completeness, "")
        suffix = f" — {guidance}" if guidance else ""
        lines.append(f"- Completeness (required: {completeness}){suffix}")

    quality = _normalize_key(fossil_data.get("llm_imp_preservation_quality"))
    if quality:
        guidance = _LLM_QUALITY_GUIDANCE.get(quality, "")
        suffix = f" — {guidance}" if guidance else ""
        lines.append(f"- Preservation quality (required: {quality}){suffix}")

    if not lines:
        lines.append(
            "- Partial in-situ exposure in natural matrix; imperfect field documentation only."
        )

    return "\n".join(lines)


def build_fossil_image_prompt(fossil_data: dict[str, Any], *, dinosaur_name: str) -> str:
    """Build Imagen prompt for a fossil occurrence card image."""
    dinosaur = dinosaur_name.strip() or "dinosaur"
    spec_brief = build_fossil_preservation_brief(fossil_data)
    return _FOSSIL_INSTRUCTIONS.format(
        dinosaur=dinosaur,
        spec_brief=spec_brief,
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
