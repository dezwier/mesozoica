"""Extract size hints from Wikipedia HTML/text for LLM prompts."""

from __future__ import annotations

import re

from bs4 import BeautifulSoup

_LENGTH_OF_RE = re.compile(
    r"length of\s+(\d+(?:\.\d+)?)\s*(metres?|meters?|m)\b",
    re.IGNORECASE,
)
_MASS_OF_RE = re.compile(
    r"(?:mass|weight) of\s+(\d+(?:\.\d+)?)\s*(tonnes?|tons?|kg|kilograms?|t)\b",
    re.IGNORECASE,
)
_ESTIMATED_SIZE_RE = re.compile(
    r"estimated to have reached a length of\s+(\d+(?:\.\d+)?)\s*(metres?|meters?|m)\b"
    r".{0,120}?(?:mass|weight) of\s+(\d+(?:\.\d+)?)\s*(tonnes?|tons?|kg|kilograms?|t)\b",
    re.IGNORECASE | re.DOTALL,
)
_LENGTH_ESTIMATED_RE = re.compile(
    r"length was estimated to be\s+(\d+(?:\.\d+)?)\s*(metres?|meters?|m)\b",
    re.IGNORECASE,
)
_GAVE_LENGTH_RE = re.compile(
    r"gave a (?:possible )?length of\s+(\d+(?:\.\d+)?)\s*(metres?|meters?|m)\b",
    re.IGNORECASE,
)
_REACHED_LENGTH_RE = re.compile(
    r"(?:reached|measuring|measured|about|approximately|estimated at|no more than)"
    r"\s+(?:about\s+)?(\d+(?:\.\d+)?)\s*(metres?|meters?|m)\b",
    re.IGNORECASE,
)
_METRES_LONG_RE = re.compile(
    r"(\d+(?:\.\d+)?)\s*(metres?|meters?|m)\s*\([^)]*\)\s*long\b",
    re.IGNORECASE,
)
_WEIGHT_AT_RE = re.compile(
    r"weight at\s+(\d+(?:\.\d+)?)\s*(tonnes?|tons?|kg|kilograms?|t)\b",
    re.IGNORECASE,
)
_KG_OR_LESS_RE = re.compile(
    r"(\d+(?:\.\d+)?)\s*kg or less\b",
    re.IGNORECASE,
)
_SIZE_PAIR_RE = re.compile(
    r"(\d+(?:\.\d+)?)\s*(metres?|meters?|m)\b.{0,160}?and\s+"
    r"(\d+(?:\.\d+)?)\s*(tonnes?|tons?|kg|kilograms?|t)\b",
    re.IGNORECASE | re.DOTALL,
)


def _format_length(value: str, unit: str) -> str:
    unit = unit.lower().rstrip("s")
    if unit in {"metre", "meter", "m"}:
        return f"{value} m"
    return f"{value} {unit}"


def _format_mass(value: str, unit: str) -> str:
    unit = unit.lower().rstrip("s")
    if unit in {"tonne", "ton", "t"}:
        return f"{value} t"
    if unit in {"kilogram", "kg"}:
        return f"{value} kg"
    return f"{value} {unit}"


def _set_length(hints: dict[str, str], value: str, unit: str) -> None:
    hints.setdefault("length_hint", _format_length(value, unit))


def _set_mass(hints: dict[str, str], value: str, unit: str) -> None:
    hints.setdefault("mass_hint", _format_mass(value, unit))


def extract_size_from_text(text: str) -> dict[str, str]:
    """Parse common size phrases from article plain text."""
    if not text or not text.strip():
        return {}

    hints: dict[str, str] = {}

    combined = _ESTIMATED_SIZE_RE.search(text)
    if combined:
        _set_length(hints, combined.group(1), combined.group(2))
        _set_mass(hints, combined.group(3), combined.group(4))

    pair = _SIZE_PAIR_RE.search(text)
    if pair:
        _set_length(hints, pair.group(1), pair.group(2))
        _set_mass(hints, pair.group(3), pair.group(4))

    for pattern in (
        _LENGTH_ESTIMATED_RE,
        _GAVE_LENGTH_RE,
        _LENGTH_OF_RE,
        _REACHED_LENGTH_RE,
        _METRES_LONG_RE,
    ):
        match = pattern.search(text)
        if match:
            _set_length(hints, match.group(1), match.group(2))
            break

    for pattern in (_MASS_OF_RE, _WEIGHT_AT_RE):
        match = pattern.search(text)
        if match:
            _set_mass(hints, match.group(1), match.group(2))
            break

    kg_match = _KG_OR_LESS_RE.search(text)
    if kg_match:
        _set_mass(hints, kg_match.group(1), "kg")

    return hints


def extract_size_hints(html: str) -> dict[str, str]:
    """Return infobox and article-text length/mass hints keyed for the enrichment prompt."""
    if not html or not html.strip():
        return {}

    hints: dict[str, str] = {}
    soup = BeautifulSoup(html, "html.parser")
    box = soup.select_one("table.infobox.biota") or soup.select_one("table.infobox")
    if box:
        for row in box.select("tr"):
            th = row.find("th")
            td = row.find("td")
            if not th or not td:
                continue
            label = th.get_text(" ", strip=True).lower()
            value = td.get_text(" ", strip=True)
            if not value:
                continue
            if label in {"length", "height", "size", "body length"} or "length" in label:
                hints.setdefault("length_hint", value)
            elif label in {"mass", "weight", "body mass", "body weight"} or "mass" in label or "weight" in label:
                hints.setdefault("mass_hint", value)

    article_text = soup.get_text(" ", strip=True)
    text_hints = extract_size_from_text(article_text)
    for key, value in text_hints.items():
        hints.setdefault(key, value)

    return hints
