"""Parse free-form dinosaur length/mass display strings into numeric ranges."""

from __future__ import annotations

import re
from typing import Literal

# Optional leading ~ / approx, then one or two numbers, then a unit.
_SIZE_RE = re.compile(
    r"""
    ^\s*
    ~?\s*
    (?P<a>\d+(?:[.,]\d+)?)
    (?:
        \s*[-–—]\s*
        (?P<b>\d+(?:[.,]\d+)?)
    )?
    \s*
    (?P<unit>cm|m|kg|t|tonnes?|tons?)
    \s*$
    """,
    re.IGNORECASE | re.VERBOSE,
)


def _to_float(raw: str) -> float:
    return float(raw.replace(",", "."))


def parse_length_m(value: str | None) -> tuple[float, float] | None:
    """Parse a length string into (min_m, max_m). Returns None if unparseable."""
    return _parse_size(value, kind="length")


def parse_mass_kg(value: str | None) -> tuple[float, float] | None:
    """Parse a mass string into (min_kg, max_kg). Returns None if unparseable."""
    return _parse_size(value, kind="mass")


def ranges_overlap(
    a_min: float,
    a_max: float,
    b_min: float,
    b_max: float,
) -> bool:
    """True when [a_min, a_max] overlaps [b_min, b_max] (inclusive)."""
    return a_min <= b_max and b_min <= a_max


def _parse_size(
    value: str | None,
    *,
    kind: Literal["length", "mass"],
) -> tuple[float, float] | None:
    if value is None:
        return None
    text = value.strip()
    if not text:
        return None

    match = _SIZE_RE.match(text)
    if match is None:
        return None

    a = _to_float(match.group("a"))
    b_raw = match.group("b")
    b = _to_float(b_raw) if b_raw is not None else a
    unit = match.group("unit").lower()

    if kind == "length":
        if unit == "cm":
            factor = 0.01
        elif unit == "m":
            factor = 1.0
        else:
            return None
    else:
        if unit == "kg":
            factor = 1.0
        elif unit in ("t", "ton", "tons", "tonne", "tonnes"):
            factor = 1000.0
        else:
            return None

    lo = min(a, b) * factor
    hi = max(a, b) * factor
    return lo, hi
