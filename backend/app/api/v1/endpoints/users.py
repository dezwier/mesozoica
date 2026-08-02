"""User profile and directory endpoints."""

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlmodel import Session, select

from app.core.database import get_session
from app.core.security import get_current_admin_user, get_current_user
from app.models.user import User
from app.schemas.auth import (
    UpdateDistanceRequest,
    UpdateSkillXpRequest,
    UserListResponse,
    UserProfileResponse,
)
from app.services.level_service import set_skill_xp, sync_career_from_skills
from app.services.level_service.skills import skill_by_id
from app.services.user_service import user_to_list_entry, user_to_profile_response
from app.services.walk_distance_service import apply_distance_update

router = APIRouter(prefix="/users", tags=["users"])


@router.get("/me", response_model=UserProfileResponse)
async def get_my_profile(
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    return user_to_profile_response(session, current_user)


@router.patch("/me/distance", response_model=UserProfileResponse)
async def update_my_distance(
    payload: UpdateDistanceRequest,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    # Re-load so we mutate a session-bound instance.
    user = session.get(User, current_user.id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
    return apply_distance_update(session, user, payload)


@router.patch("/me/skills/{skill_id}/xp", response_model=UserProfileResponse)
async def update_my_skill_xp(
    skill_id: str,
    payload: UpdateSkillXpRequest,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_admin_user),
):
    """Admin-only: set absolute XP for one of the caller's skills."""
    if skill_by_id(skill_id) is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Unknown skill id: {skill_id}",
        )
    user = session.get(User, current_user.id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
    set_skill_xp(user, skill_id, payload.xp)
    sync_career_from_skills(user)
    session.add(user)
    session.commit()
    session.refresh(user)
    return user_to_profile_response(session, user)


@router.get("/list", response_model=UserListResponse)
async def get_all_users(
    offset: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=200),
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    del current_user
    users = session.exec(
        select(User).order_by(User.username.asc()).offset(offset).limit(limit + 1)
    ).all()
    has_next = len(users) > limit
    page_users = users[:limit]
    total = session.exec(select(User)).all()
    return UserListResponse(
        items=[user_to_list_entry(session, user) for user in page_users],
        total=len(total),
        limit=limit,
        offset=offset,
        has_next=has_next,
    )


@router.get("/{user_id}/profile", response_model=UserProfileResponse)
async def get_user_profile(
    user_id: int,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    del current_user
    user = session.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
    return user_to_profile_response(session, user)
