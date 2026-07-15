"""User relationship endpoints (friend requests + block)."""

from __future__ import annotations

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlmodel import Session, or_, select

from app.core.database import get_session
from app.core.security import get_current_user
from app.models.user import User
from app.models.user_user import UserUser
from app.schemas.auth import UserResponse
from app.schemas.user_relationship import (
    LeaderboardEntry,
    LeaderboardResponse,
    UserRelationshipActionRequest,
    UserRelationshipResponse,
)
from app.services.user_service import user_to_response

router = APIRouter(prefix="/user-relationships", tags=["user-relationships"])


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _pair(a: int, b: int) -> tuple[int, int]:
    return (a, b) if a < b else (b, a)


def _get_row(session: Session, a: int, b: int) -> UserUser | None:
    p1, p2 = _pair(a, b)
    return session.exec(
        select(UserUser).where(UserUser.user_id1 == p1, UserUser.user_id2 == p2)
    ).first()


def _require_target(session: Session, current_user_id: int, target_user_id: int) -> User:
    if target_user_id == current_user_id:
        raise HTTPException(status_code=400, detail="Cannot perform this action on yourself")
    target = session.get(User, target_user_id)
    if target is None:
        raise HTTPException(status_code=404, detail="Target user not found")
    return target


def _to_response(target_user_id: int, row: UserUser | None) -> UserRelationshipResponse:
    if row is None:
        return UserRelationshipResponse(target_user_id=target_user_id, relationship_type="none")
    return UserRelationshipResponse(
        target_user_id=target_user_id,
        relationship_type=row.relationship_type,
        action_user_id=row.action_user_id,
        created_at=row.created_at,
        updated_at=row.updated_at,
    )


@router.get("/{target_user_id}", response_model=UserRelationshipResponse)
async def get_user_relationship(
    target_user_id: int,
    current_user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    if target_user_id == current_user.id:
        return UserRelationshipResponse(
            target_user_id=target_user_id,
            relationship_type="self",
        )
    target = session.get(User, target_user_id)
    if target is None:
        raise HTTPException(status_code=404, detail="Target user not found")
    return _to_response(target_user_id, _get_row(session, current_user.id, target_user_id))


@router.post("/friend-request", response_model=UserRelationshipResponse)
async def send_friend_request(
    body: UserRelationshipActionRequest,
    current_user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    target_user_id = body.target_user_id
    _require_target(session, current_user.id, target_user_id)
    now = _utc_now()
    row = _get_row(session, current_user.id, target_user_id)
    if row and row.relationship_type == "blocked":
        raise HTTPException(status_code=409, detail="Cannot send friend request while blocked")
    if row is None:
        p1, p2 = _pair(current_user.id, target_user_id)
        row = UserUser(
            user_id1=p1,
            user_id2=p2,
            relationship_type="friend_pending",
            action_user_id=current_user.id,
            created_at=now,
            updated_at=now,
        )
    else:
        row.relationship_type = "friend_pending"
        row.action_user_id = current_user.id
        row.updated_at = now
    session.add(row)
    session.commit()
    session.refresh(row)
    return _to_response(target_user_id, row)


@router.post("/friend-request/{target_user_id}/cancel", response_model=UserRelationshipResponse)
async def cancel_friend_request(
    target_user_id: int,
    current_user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    _require_target(session, current_user.id, target_user_id)
    row = _get_row(session, current_user.id, target_user_id)
    if row is None or row.relationship_type != "friend_pending" or row.action_user_id != current_user.id:
        raise HTTPException(status_code=404, detail="No outgoing friend request found")
    session.delete(row)
    session.commit()
    return UserRelationshipResponse(target_user_id=target_user_id, relationship_type="none")


@router.post("/friend/{target_user_id}/remove", response_model=UserRelationshipResponse)
async def remove_friend(
    target_user_id: int,
    current_user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    _require_target(session, current_user.id, target_user_id)
    row = _get_row(session, current_user.id, target_user_id)
    if row is None or row.relationship_type != "friend":
        raise HTTPException(status_code=404, detail="No friendship found")
    session.delete(row)
    session.commit()
    return UserRelationshipResponse(target_user_id=target_user_id, relationship_type="none")


@router.get("/friends/me/list", response_model=LeaderboardResponse)
async def get_my_friends_list(
    offset: int = Query(0, ge=0),
    limit: int = Query(5, ge=1, le=100),
    current_user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    rows = session.exec(
        select(UserUser).where(
            UserUser.relationship_type == "friend",
            or_(
                UserUser.user_id1 == current_user.id,
                UserUser.user_id2 == current_user.id,
            ),
        )
    ).all()

    friend_ids: list[int] = []
    for row in rows:
        friend_ids.append(row.user_id2 if row.user_id1 == current_user.id else row.user_id1)

    friends: list[User] = []
    if friend_ids:
        friends = session.exec(
            select(User).where(User.id.in_(friend_ids)).order_by(User.username.asc())
        ).all()

    total = len(friends)
    start_idx = offset
    end_idx = min(offset + limit, total)
    paginated_friends = friends[start_idx:end_idx]
    page_size = limit
    page = (offset // limit) + 1 if limit else 1
    total_pages = (total + page_size - 1) // page_size if total > 0 else 0

    entries: list[LeaderboardEntry] = []
    for idx, user in enumerate(paginated_friends, start=start_idx + 1):
        entries.append(
            LeaderboardEntry(
                user=UserResponse(**user_to_response(user).model_dump()),
                count=0,
                rank=idx,
            )
        )

    return LeaderboardResponse(
        entries=entries,
        total=total,
        page=page,
        page_size=page_size,
        total_pages=total_pages,
    )
