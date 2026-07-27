"""User profile and directory helpers."""

from __future__ import annotations

from sqlalchemy import delete, func
from sqlmodel import Session, col, select

from app.core.exceptions import ValidationError
from app.models.user import User
from app.models.user_dinosaur import UserDinosaur
from app.models.user_fossil import UserFossil
from app.models.user_site import UserSite
from app.schemas.auth import UserListEntry, UserProfileResponse, UserResponse


def collection_counts(session: Session, user_id: int) -> dict[str, int]:
    """Unique sites / fossils / dinosaurs linked to the user."""
    sites = session.exec(
        select(func.count(func.distinct(UserSite.site_id))).where(
            col(UserSite.user_id) == user_id
        )
    ).one()
    fossils = session.exec(
        select(func.count(func.distinct(UserFossil.fossil_id))).where(
            col(UserFossil.user_id) == user_id
        )
    ).one()
    dinosaurs = session.exec(
        select(func.count(func.distinct(UserDinosaur.dinosaur_id))).where(
            col(UserDinosaur.user_id) == user_id
        )
    ).one()
    return {
        "actual_sites_count": int(sites or 0),
        "actual_fossils_count": int(fossils or 0),
        "actual_dinosaurs_count": int(dinosaurs or 0),
    }


def _count_rows(session: Session, model: type, user_id: int) -> int:
    count = session.exec(
        select(func.count()).select_from(model).where(col(model.user_id) == user_id)
    ).one()
    return int(count or 0)


def delete_user_progress(
    session: Session,
    user_id: int,
    *,
    sites: bool,
    fossils: bool,
    dinosaurs: bool,
) -> dict[str, int]:
    """Bulk-delete selected progress rows for one user. Idempotent."""
    if not (sites or fossils or dinosaurs):
        raise ValidationError("Select at least one data category to delete")

    deleted_sites = 0
    deleted_fossils = 0
    deleted_dinosaurs = 0

    if sites:
        deleted_sites = _count_rows(session, UserSite, user_id)
        session.exec(delete(UserSite).where(col(UserSite.user_id) == user_id))
    if fossils:
        deleted_fossils = _count_rows(session, UserFossil, user_id)
        session.exec(delete(UserFossil).where(col(UserFossil.user_id) == user_id))
    if dinosaurs:
        deleted_dinosaurs = _count_rows(session, UserDinosaur, user_id)
        session.exec(delete(UserDinosaur).where(col(UserDinosaur.user_id) == user_id))

    session.commit()
    return {
        "deleted_sites": deleted_sites,
        "deleted_fossils": deleted_fossils,
        "deleted_dinosaurs": deleted_dinosaurs,
    }


def user_to_response(user: User) -> UserResponse:
    from app.services.level_service import (
        career_title_for_user_xp,
        level_for_xp,
        progress_in_level,
    )

    display = user.display_name or user.full_name or user.username
    exploration_xp = int(user.exploration_xp or 0)
    excavation_xp = int(user.excavation_xp or 0)
    research_xp = int(user.research_xp or 0)
    career_xp = exploration_xp + excavation_xp + research_xp
    return UserResponse(
        id=user.id,
        username=user.username,
        email=user.email,
        created_at=user.created_at.isoformat(),
        full_name=user.full_name,
        image_url=user.image_url,
        display_name=display,
        specialization=user.specialization,
        years_of_experience=user.years_of_experience,
        notable_discovery=user.notable_discovery,
        favorite_era=user.favorite_era,
        xp=career_xp,
        level=level_for_xp(career_xp, career=True),
        achievements=list(user.achievements or []),
        bio=user.bio,
        current_location=user.current_location,
        is_subscriber=False,
        is_admin=user.is_admin,
        total_distance_m=float(user.total_distance_m or 0.0),
        weekly_distance_m=float(user.weekly_distance_m or 0.0),
        active_distance_m=float(user.active_distance_m or 0.0),
        active_weekly_distance_m=float(user.active_weekly_distance_m or 0.0),
        distance_week_start=user.distance_week_start,
        distance_synced_at=(
            user.distance_synced_at.isoformat()
            if user.distance_synced_at is not None
            else None
        ),
        exploration_xp=exploration_xp,
        excavation_xp=excavation_xp,
        research_xp=research_xp,
        exploration_level=level_for_xp(exploration_xp),
        excavation_level=level_for_xp(excavation_xp),
        research_level=level_for_xp(research_xp),
        career_title=career_title_for_user_xp(
            exploration_xp, excavation_xp, research_xp
        ),
        exploration_progress=progress_in_level(exploration_xp),
        excavation_progress=progress_in_level(excavation_xp),
        research_progress=progress_in_level(research_xp),
        career_progress=progress_in_level(career_xp, career=True),
        xp_from_sites=int(user.xp_from_sites or 0),
        xp_from_fossils=int(user.xp_from_fossils or 0),
        xp_from_active_distance=int(user.xp_from_active_distance or 0),
        xp_from_passive_distance=int(user.xp_from_passive_distance or 0),
    )


def user_to_profile_response(session: Session, user: User) -> UserProfileResponse:
    counts = collection_counts(session, user.id)
    base = user_to_response(user).model_dump()
    return UserProfileResponse(**base, **counts)


def user_to_list_entry(session: Session, user: User) -> UserListEntry:
    from app.services.level_service import level_for_xp

    counts = collection_counts(session, user.id)
    career_xp = (
        int(user.exploration_xp or 0)
        + int(user.excavation_xp or 0)
        + int(user.research_xp or 0)
    )
    return UserListEntry(
        id=user.id,
        username=user.username,
        display_name=user.display_name or user.full_name or user.username,
        full_name=user.full_name,
        image_url=user.image_url,
        level=level_for_xp(career_xp, career=True),
        **counts,
    )


def delete_user_account(session: Session, user: User) -> None:
    from app.models.user_auth_identity import UserAuthIdentity
    from app.models.user_user import UserUser
    from app.services.firebase_auth_service import delete_firebase_user

    if user.firebase_uid:
        delete_firebase_user(user.firebase_uid)

    identities = session.exec(
        select(UserAuthIdentity).where(UserAuthIdentity.user_id == user.id)
    ).all()
    for identity in identities:
        session.delete(identity)

    relationships = session.exec(
        select(UserUser).where(
            (UserUser.user_id1 == user.id)
            | (UserUser.user_id2 == user.id)
            | (UserUser.action_user_id == user.id)
        )
    ).all()
    for relationship in relationships:
        session.delete(relationship)

    session.delete(user)
    session.commit()
