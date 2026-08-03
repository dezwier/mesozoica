"""Site exploration distance sync (meters inside site_visibility_m)."""

from __future__ import annotations

from fastapi import HTTPException, status
from sqlmodel import Session, col, select

from app.models.data_source import DATA_SOURCE_FIELD
from app.models.user import User
from app.models.user_site import USER_SITE_ROLE_DISCOVERER, UserSite
from app.schemas.auth import UserProfileResponse
from app.schemas.site import SiteExplorationUpdateRequest, SiteSummary
from app.services.level_service import (
    award_site_exploration_xp,
    get_skill_xp,
    level_for_xp,
)
from app.services.site_service.list import get_site_by_id
from app.services.site_service.summary import site_row_to_summary
from app.services.user_service import user_to_profile_response

# Cap reported growth vs last value (~50 km/day per site) to blunt trivial tampering.
_MAX_METERS_PER_DAY = 50_000.0


def _monotonic(previous: float, reported: float) -> float:
    return previous if reported < previous else reported


def apply_site_exploration_update(
    session: Session,
    user: User,
    payload: SiteExplorationUpdateRequest,
) -> tuple[UserProfileResponse, list[SiteSummary]]:
    """Monotonically update discoverer explored_distance_m and award XP batches."""
    if not payload.sites:
        return user_to_profile_response(session, user), []

    site_ids = [int(entry.site_id) for entry in payload.sites]
    links = session.exec(
        select(UserSite).where(
            col(UserSite.user_id) == int(user.id),
            col(UserSite.site_id).in_(site_ids),
            col(UserSite.role) == USER_SITE_ROLE_DISCOVERER,
        )
    ).all()
    by_site = {int(link.site_id): link for link in links}

    updated_ids: list[int] = []
    for entry in payload.sites:
        link = by_site.get(int(entry.site_id))
        if link is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Discovered site {entry.site_id} not found for user",
            )
        previous = float(link.explored_distance_m or 0.0)
        reported = float(entry.explored_distance_m)
        new_value = _monotonic(previous, reported)
        delta = new_value - previous
        if delta > _MAX_METERS_PER_DAY:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=(
                    "Explored distance increase exceeds the allowed rate "
                    f"({delta:.0f}m for site {entry.site_id})."
                ),
            )
        if delta > 0:
            award_site_exploration_xp(
                user,
                previous_explored_m=previous,
                new_explored_m=new_value,
            )
            link.explored_distance_m = new_value
            session.add(link)
            updated_ids.append(int(entry.site_id))

    session.add(user)
    session.commit()
    session.refresh(user)

    skill_level = level_for_xp(get_skill_xp(user, "site_stewardship"))
    summaries: list[SiteSummary] = []
    for site_id in updated_ids:
        row = get_site_by_id(
            session,
            site_id,
            data_source=DATA_SOURCE_FIELD,
            viewer_user_id=int(user.id),
        )
        summaries.append(
            site_row_to_summary(
                row,
                survey_skill_level=skill_level,
            )
        )

    return user_to_profile_response(session, user), summaries
