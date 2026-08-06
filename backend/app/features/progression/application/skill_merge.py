"""Helpers to collapse the legacy 12 skill keys into field_survey / bone_quarry / science_hall."""

from __future__ import annotations

from typing import Any

SKILL_MERGE: dict[str, str] = {
    "site_discovery": "field_survey",
    "site_stewardship": "field_survey",
    "site_clearing": "field_survey",
    "fossil_detection": "bone_quarry",
    "fossil_excavation": "bone_quarry",
    "fossil_transport": "bone_quarry",
    "fossil_curation": "bone_quarry",
    "fossil_preparation": "science_hall",
    "fossil_analysis": "science_hall",
    "dinosaur_modelling": "science_hall",
    "dinosaur_mounting": "science_hall",
    "academic_publishing": "science_hall",
}

TARGET_SKILLS = frozenset({"field_survey", "bone_quarry", "science_hall"})


def merge_skill_xp(skill_xp: dict[str, Any] | None) -> dict[str, int]:
    """Sum XP from old skill keys into the three target skills."""
    out: dict[str, int] = {
        "field_survey": 0,
        "bone_quarry": 0,
        "science_hall": 0,
    }
    if not skill_xp:
        return out
    for key, raw in skill_xp.items():
        target = SKILL_MERGE.get(str(key), str(key))
        if target not in TARGET_SKILLS:
            continue
        out[target] += max(0, int(raw or 0))
    return out


def merge_skill_breakdown(
    breakdown: dict[str, Any] | None,
) -> dict[str, dict[str, int]]:
    """Merge per-skill breakdown maps into the three target skills."""
    out: dict[str, dict[str, int]] = {}
    if not breakdown:
        return out
    for key, bucket in breakdown.items():
        target = SKILL_MERGE.get(str(key), str(key))
        if target not in TARGET_SKILLS or not isinstance(bucket, dict):
            continue
        dest = out.setdefault(target, {})
        for source_key, raw in bucket.items():
            dest[str(source_key)] = int(dest.get(str(source_key), 0)) + int(raw or 0)
    return out
