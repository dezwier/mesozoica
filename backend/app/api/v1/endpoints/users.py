"""User profile and directory endpoints."""

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlmodel import Session, select

from app.core.database import get_session
from app.core.security import get_current_user
from app.models.user import User
from app.schemas.auth import UserListResponse, UserProfileResponse
from app.services.user_service import user_to_list_entry, user_to_profile_response

router = APIRouter(prefix="/users", tags=["users"])


@router.get("/me", response_model=UserProfileResponse)
async def get_my_profile(
    current_user: User = Depends(get_current_user),
):
    return user_to_profile_response(current_user)


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
        items=[user_to_list_entry(user) for user in page_users],
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
    return user_to_profile_response(user)
