"""Career / skill leveling helpers."""

from app.services.level_service.award import (
    award_distance_km_xp,
    award_fossil_discover_xp,
    award_site_discover_xp,
    award_skill_xp,
    award_successful_site_disguise_xp,
    passive_meters,
    sync_career_from_skills,
    whole_km,
)
from app.services.level_service.backfill import backfill_all_users, backfill_user_levels
from app.services.level_service.skills import (
    all_skill_states,
    career_state,
    get_skill_xp,
    set_skill_xp,
    skill_count,
    skill_state,
    total_skill_xp,
)
from app.services.level_service.titles import career_title_for_level, career_title_for_user_xp
from app.services.level_service.xp_table import (
    CAREER_MAX_LEVEL,
    CAREER_THRESHOLDS,
    SKILL_MAX_LEVEL,
    SKILL_THRESHOLDS,
    get_career_thresholds,
    level_for_xp,
    next_level_xp,
    progress_in_level,
    xp_for_level,
    xp_to_next_level,
)

__all__ = [
    "CAREER_MAX_LEVEL",
    "CAREER_THRESHOLDS",
    "SKILL_MAX_LEVEL",
    "SKILL_THRESHOLDS",
    "all_skill_states",
    "award_distance_km_xp",
    "award_fossil_discover_xp",
    "award_site_discover_xp",
    "award_skill_xp",
    "award_successful_site_disguise_xp",
    "backfill_all_users",
    "backfill_user_levels",
    "career_state",
    "career_title_for_level",
    "career_title_for_user_xp",
    "get_career_thresholds",
    "get_skill_xp",
    "level_for_xp",
    "next_level_xp",
    "passive_meters",
    "progress_in_level",
    "set_skill_xp",
    "skill_count",
    "skill_state",
    "sync_career_from_skills",
    "total_skill_xp",
    "whole_km",
    "xp_for_level",
    "xp_to_next_level",
]
