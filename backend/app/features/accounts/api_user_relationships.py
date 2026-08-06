"""User relationship endpoints (friend requests + block). Owned by the accounts feature."""

from __future__ import annotations

from fastapi import APIRouter, Depends, Query
from sqlmodel import Session

from app.core.database import get_session
from app.core.security import get_current_user
from app.models.user import User
from app.schemas.user_relationship import (
    LeaderboardResponse,
    UserRelationshipActionRequest,
    UserRelationshipResponse,
)
from app.features.accounts.application import relationships

router = APIRouter(prefix="/user-relationships", tags=["user-relationships"])


@router.get("/{target_user_id}", response_model=UserRelationshipResponse)
async def get_user_relationship(
    target_user_id: int,
    current_user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    return relationships.get_user_relationship(
        session,
        current_user_id=current_user.id,
        target_user_id=target_user_id,
    )


@router.post("/friend-request", response_model=UserRelationshipResponse)
async def send_friend_request(
    body: UserRelationshipActionRequest,
    current_user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    return relationships.send_friend_request(
        session,
        current_user_id=current_user.id,
        target_user_id=body.target_user_id,
    )


@router.post("/friend-request/{target_user_id}/accept", response_model=UserRelationshipResponse)
async def accept_friend_request(
    target_user_id: int,
    current_user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    return relationships.accept_friend_request(
        session,
        current_user_id=current_user.id,
        target_user_id=target_user_id,
    )


@router.post("/friend-request/{target_user_id}/reject", response_model=UserRelationshipResponse)
async def reject_friend_request(
    target_user_id: int,
    current_user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    return relationships.reject_friend_request(
        session,
        current_user_id=current_user.id,
        target_user_id=target_user_id,
    )


@router.post("/friend-request/{target_user_id}/cancel", response_model=UserRelationshipResponse)
async def cancel_friend_request(
    target_user_id: int,
    current_user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    return relationships.cancel_friend_request(
        session,
        current_user_id=current_user.id,
        target_user_id=target_user_id,
    )


@router.post("/friend/{target_user_id}/remove", response_model=UserRelationshipResponse)
async def remove_friend(
    target_user_id: int,
    current_user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    return relationships.remove_friend(
        session,
        current_user_id=current_user.id,
        target_user_id=target_user_id,
    )


@router.get("/friends/me/list", response_model=LeaderboardResponse)
async def get_my_friends_list(
    offset: int = Query(0, ge=0),
    limit: int = Query(5, ge=1, le=100),
    current_user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    return relationships.list_friends(
        session,
        current_user_id=current_user.id,
        offset=offset,
        limit=limit,
    )
