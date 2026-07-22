"""User profile and directory helpers."""

from __future__ import annotations

from sqlmodel import Session, select

from app.models.user import User
from app.schemas.auth import UserListEntry, UserProfileResponse, UserResponse


def collection_counts(_user_id: int) -> dict[str, int]:
    """Placeholder until user inventory tables exist."""
    return {
        "actual_dinosaurs_count": 0,
        "actual_fossils_count": 0,
        "actual_sites_count": 0,
    }


def user_to_response(user: User) -> UserResponse:
    display = user.display_name or user.full_name or user.username
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
        xp=user.xp,
        level=user.level,
        achievements=list(user.achievements or []),
        bio=user.bio,
        current_location=user.current_location,
        is_subscriber=False,
        is_admin=user.is_admin,
        total_distance_m=float(user.total_distance_m or 0.0),
        weekly_distance_m=float(user.weekly_distance_m or 0.0),
        distance_week_start=user.distance_week_start,
        distance_synced_at=(
            user.distance_synced_at.isoformat()
            if user.distance_synced_at is not None
            else None
        ),
    )


def user_to_profile_response(user: User) -> UserProfileResponse:
    counts = collection_counts(user.id)
    base = user_to_response(user).model_dump()
    return UserProfileResponse(**base, **counts)


def user_to_list_entry(user: User) -> UserListEntry:
    counts = collection_counts(user.id)
    return UserListEntry(
        id=user.id,
        username=user.username,
        display_name=user.display_name or user.full_name or user.username,
        full_name=user.full_name,
        image_url=user.image_url,
        level=user.level,
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
