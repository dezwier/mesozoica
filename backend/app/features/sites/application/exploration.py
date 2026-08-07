"""Time-based site documentation progress sync."""

from __future__ import annotations

from fastapi import HTTPException, status
from sqlmodel import Session, col, select

from app.shared.data_sources import DATA_SOURCE_FIELD
from app.models.user import User
from app.models.user_notification import UserNotification, UserNotificationType
from app.models.user_site import (
    USER_SITE_ROLE_DISCOVERER,
    USER_SITE_ROLE_DOCUMENTER,
    USER_SITE_ROLE_IDENTIFIER,
    UserSite,
)
from app.schemas.auth import UserProfileResponse
from app.schemas.site import SiteExplorationUpdateRequest, SiteSummary
from app.features.progression.public import (
    award_document_site_as_first_xp,
    award_document_site_xp,
    get_skill_xp,
    level_for_xp,
)
from app.features.accounts.public import (
    CelebrationNotificationDescriptor,
    create_site_celebration_notification,
    deliver_site_celebration_notification,
    send_site_documented_push,
    user_to_profile_response,
)
from app.features.sites.domain.labels import site_display_title
from app.features.sites.application.dimension_display import site_is_fully_documented
from app.features.sites.application.list import get_site_by_id
from app.features.sites.application.summary import site_row_to_summary

def _viewer_has_identified(
    session: Session, *, user_id: int, site_id: int, link: UserSite
) -> bool:
    if bool(link.period_identified and link.rock_identified):
        return True
    row = session.exec(
        select(UserSite.id).where(
            col(UserSite.user_id) == user_id,
            col(UserSite.site_id) == site_id,
            col(UserSite.role) == USER_SITE_ROLE_IDENTIFIER,
        )
    ).first()
    return row is not None


def _monotonic(previous: float, reported: float) -> float:
    return previous if reported < previous else reported


def _upsert_documenter(
    session: Session, *, user_id: int, site_id: int, was_first: bool
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
            was_first=was_first,
        )
        session.add(row)
        return row
    existing.timestamp = now
    if was_first and not bool(existing.was_first):
        existing.was_first = True
    session.add(existing)
    return existing


def _maybe_complete_documentation(
    session: Session,
    user: User,
    link: UserSite,
    *,
    skill_level: int,
) -> UserNotification | None:
    """Award documentation XP and freeze the site when all dims hit 100%.

    Returns a new inbox notification when documentation was completed in this
    call; otherwise None.
    """
    if bool(link.documented):
        return None
    row = get_site_by_id(
        session,
        int(link.site_id),
        data_source=DATA_SOURCE_FIELD,
        viewer_user_id=int(user.id),
    )
    site = row.site
    progress = float(link.documentation_progress or 0.0)
    if not site_is_fully_documented(
        site_id=int(site.site_id),
        odd_dino_count=site.odd_dino_count,
        odd_fossil_count=site.odd_fossil_count,
        odd_completeness=site.odd_completeness,
        odd_quality=site.odd_quality,
        odd_depth=site.odd_depth,
        skill_level=skill_level,
        documentation_progress=progress,
    ):
        return None
    existing_documenter = session.exec(
        select(UserSite).where(
            col(UserSite.site_id) == int(link.site_id),
            col(UserSite.role) == USER_SITE_ROLE_DOCUMENTER,
        )
    ).first()
    is_document_site_as_first = existing_documenter is None
    award_document_site_xp(user)
    if is_document_site_as_first:
        award_document_site_as_first_xp(user)
    link.documented = True
    session.add(link)
    _upsert_documenter(
        session,
        user_id=int(user.id),
        site_id=int(link.site_id),
        was_first=is_document_site_as_first,
    )
    notification = create_site_celebration_notification(
        session,
        user_id=int(user.id),
        site_id=int(link.site_id),
        notification_type=UserNotificationType.SITE_DOCUMENTED,
    )
    return notification


def apply_site_exploration_update(
    session: Session,
    user: User,
    payload: SiteExplorationUpdateRequest,
    *,
    celebrations_out: list[CelebrationNotificationDescriptor] | None = None,
) -> tuple[UserProfileResponse, list[SiteSummary]]:
    """Monotonically update discoverer documentation progress.

    Documented sites refuse further progress. Crossing 100% accuracy on all
    five dimensions awards document_site_xp once and freezes the site.
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

    skill_level = level_for_xp(get_skill_xp(user, "field_survey"))
    updated_ids: list[int] = []
    pending_doc_notifications: list[tuple[int, UserNotification]] = []
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

        if not _viewer_has_identified(
            session,
            user_id=int(user.id),
            site_id=int(entry.site_id),
            link=link,
        ):
            # Identification is required before documentation can accrue.
            updated_ids.append(int(entry.site_id))
            continue

        previous = float(link.documentation_progress or 0.0)
        reported = float(entry.documentation_progress)
        new_value = min(1.0, _monotonic(previous, reported))
        if new_value > previous:
            link.documentation_progress = new_value
            session.add(link)

        notification = _maybe_complete_documentation(
            session, user, link, skill_level=skill_level
        )
        if notification is not None:
            pending_doc_notifications.append((int(link.site_id), notification))
        updated_ids.append(int(entry.site_id))

    session.add(user)
    session.commit()
    session.refresh(user)

    celebrations: list[CelebrationNotificationDescriptor] = []
    for site_id, notification in pending_doc_notifications:
        session.refresh(notification)
        if notification.id is None:
            continue
        row = get_site_by_id(
            session,
            site_id,
            data_source=DATA_SOURCE_FIELD,
            viewer_user_id=int(user.id),
        )
        celebration = deliver_site_celebration_notification(
            session,
            notification,
            site_label=site_display_title(row.site),
            push_sender=lambda session, **kwargs: send_site_documented_push(
                session,
                user_id=kwargs["user_id"],
                site_id=kwargs["site_id"],
                notification_id=kwargs["notification_id"],
                site_label=kwargs["site_label"],
            ),
        )
        if celebration is not None:
            celebrations.append(celebration)

    skill_level = level_for_xp(get_skill_xp(user, "field_survey"))
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

    if celebrations_out is not None:
        celebrations_out.extend(celebrations)
    return user_to_profile_response(session, user), summaries
