"""Unit tests for the 12→3 skill XP merge helpers."""

from app.services.level_service.skill_merge import (
    merge_skill_breakdown,
    merge_skill_xp,
)


def test_merge_skill_xp_sums_sources() -> None:
    merged = merge_skill_xp(
        {
            "site_discovery": 100,
            "site_stewardship": 250,
            "site_clearing": 0,
            "fossil_detection": 40,
            "fossil_excavation": 10,
            "academic_publishing": 5,
        }
    )
    assert merged == {
        "field_survey": 350,
        "bone_quarry": 50,
        "science_hall": 5,
    }


def test_merge_skill_breakdown_unions_buckets() -> None:
    merged = merge_skill_breakdown(
        {
            "site_discovery": {"sites": 40, "active_distance": 100},
            "site_stewardship": {"disguise": 40, "site_exploration": 20},
            "fossil_detection": {"fossils": 15},
        }
    )
    assert merged == {
        "field_survey": {
            "sites": 40,
            "active_distance": 100,
            "disguise": 40,
            "site_exploration": 20,
        },
        "bone_quarry": {"fossils": 15},
    }


def test_merge_empty_maps() -> None:
    assert merge_skill_xp(None) == {
        "field_survey": 0,
        "bone_quarry": 0,
        "science_hall": 0,
    }
    assert merge_skill_breakdown(None) == {}
