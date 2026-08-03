"""Site exploration distance sync (meters inside site_visibility_m)."""

from __future__ import annotations

from fastapi import HTTPException, status
from sqlmodel import Session, col, select

from app.models.data_source import DATA_SOURCE_FIELD
from app.models.user import User
from app.models.user_site import (
    USER_SITE_ROLE_DISCOVERER,
    USER_SITE_ROLE_DOCUMENTER,
    UserSite,
)
from app.schemas.auth import UserProfileResponse
from app.schemas.site import SiteExplorationUpdateRequest, SiteSummary
from app.services.level_service import (
    award_site_documentation_xp,
    award_site_exploration_xp,
    get_skill_xp,
    level_for_xp,
)
from app.services.site_service.dimension_display import site_is_fully_documented
from app.services.site_service.list import get_site_by_id
from app.services.site_service.summary import site_row_to_summary
from app.services.user_service import user_to_profile_response

# Cap reported growth vs last value (~50 km/day per site) to blunt trivial tampering.
_MAX_METERS_PER_DAY = 50_000.0


def _monotonic(previous: float, reported: float) -> float:
    return previous if reported < previous else reported


def _upsert_documenter(
    session: Session, *, user_id: int, site_id: int
) -> UserSite:
    """Record documenter role so site status becomes documented."""
    from datetime import datetime, timezone

    now = datetime.now(timezone.utc)
    existing = session.exec(
        select(UserSite).where(
            col(UserSite.user_id) == user_id,
            col(UserSite.site_id) == site_id,
            col(UserSite.role) == USER_SITE_ROLE_DOCUMENTER,
        )
    ).first()
    if existing is None:
        row = UserSite(
            user_id=user_id,
            site_id=site_id,
            role=USER_SITE_ROLE_DOCUMENTER,
            timestamp=now,
        )
        session.add(row)
        return row
    existing.timestamp = now
    session.add(existing)
    return existing


def _maybe_complete_documentation(
    session: Session,
    user: User,
    link: UserSite,
    *,
    skill_level: int,
) -> bool:
    """Award documentation XP and freeze the site when all dims hit 100%.

    Returns True when the site is documented after this call.
    """
    if bool(link.documented):
        return True
    row = get_site_by_id(
        session,
        int(link.site_id),
        data_source=DATA_SOURCE_FIELD,
        viewer_user_id=int(user.id),
    )
    site = row.site
    explored = float(link.explored_distance_m or 0.0)
    if not site_is_fully_documented(
        site_id=int(site.site_id),
        odd_dino_count=site.odd_dino_count,
        odd_fossil_count=site.odd_fossil_count,
        odd_completeness=site.odd_completeness,
        odd_quality=site.odd_quality,
        odd_depth=site.odd_depth,
        skill_level=skill_level,
        explored_distance_m=explored,
    ):
        return False
    award_site_documentation_xp(user)
    link.documented = True
    session.add(link)
    _upsert_documenter(
        session, user_id=int(user.id), site_id=int(link.site_id)
    )
    return True


def apply_site_exploration_update(
    session: Session,
    user: User,
    payload: SiteExplorationUpdateRequest,
) -> tuple[UserProfileResponse, list[SiteSummary]]:
    """Monotonically update discoverer explored_distance_m and award XP batches.

    Documented sites refuse further meter growth. Crossing 100% accuracy on all
    five dimensions awards site_documentation_xp once and freezes the site.
    """
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

    skill_level = level_for_xp(get_skill_xp(user, "site_stewardship"))
    updated_ids: list[int] = []
    for entry in payload.sites:
        link = by_site.get(int(entry.site_id))
        if link is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Discovered site {entry.site_id} not found for user",
            )

        if bool(link.documented):
            # Frozen: still return summary so clients sync the documented flag.
            updated_ids.append(int(entry.site_id))
            continue

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

        # Recompute skill level after possible exploration XP.
        skill_level = level_for_xp(get_skill_xp(user, "site_stewardship"))
        _maybe_complete_documentation(
            session, user, link, skill_level=skill_level
        )
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
                stewardship_skill_level=skill_level,
            )
        )

    return user_to_profile_response(session, user), summaries
