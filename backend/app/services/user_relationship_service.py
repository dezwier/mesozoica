"""User relationship domain logic (friend requests + friends list)."""

from __future__ import annotations

from datetime import datetime, timezone

from fastapi import HTTPException
from sqlmodel import Session, or_, select

from app.models.user import User
from app.models.user_notification import UserNotification, UserNotificationType
from app.models.user_user import UserUser
from app.schemas.auth import UserResponse
from app.schemas.user_relationship import (
    LeaderboardEntry,
    LeaderboardResponse,
    UserRelationshipResponse,
)
from app.services.user_service import user_to_response


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _pair(a: int, b: int) -> tuple[int, int]:
    return (a, b) if a < b else (b, a)


def get_relationship_row(session: Session, a: int, b: int) -> UserUser | None:
    p1, p2 = _pair(a, b)
    return session.exec(
        select(UserUser).where(UserUser.user_id1 == p1, UserUser.user_id2 == p2)
    ).first()


def require_target(session: Session, current_user_id: int, target_user_id: int) -> User:
    if target_user_id == current_user_id:
        raise HTTPException(status_code=400, detail="Cannot perform this action on yourself")
    target = session.get(User, target_user_id)
    if target is None:
        raise HTTPException(status_code=404, detail="Target user not found")
    return target


def to_relationship_response(
    target_user_id: int, row: UserUser | None
) -> UserRelationshipResponse:
    if row is None:
        return UserRelationshipResponse(
            target_user_id=target_user_id, relationship_type="none"
        )
    return UserRelationshipResponse(
        target_user_id=target_user_id,
        relationship_type=row.relationship_type,
        action_user_id=row.action_user_id,
        created_at=row.created_at,
        updated_at=row.updated_at,
    )


def get_user_relationship(
    session: Session,
    *,
    current_user_id: int,
    target_user_id: int,
) -> UserRelationshipResponse:
    if target_user_id == current_user_id:
        return UserRelationshipResponse(
            target_user_id=target_user_id,
            relationship_type="self",
        )
    target = session.get(User, target_user_id)
    if target is None:
        raise HTTPException(status_code=404, detail="Target user not found")
    return to_relationship_response(
        target_user_id, get_relationship_row(session, current_user_id, target_user_id)
    )


def send_friend_request(
    session: Session,
    *,
    current_user_id: int,
    target_user_id: int,
) -> UserRelationshipResponse:
    require_target(session, current_user_id, target_user_id)
    now = _utc_now()
    row = get_relationship_row(session, current_user_id, target_user_id)
    if row and row.relationship_type == "blocked":
        raise HTTPException(
            status_code=409, detail="Cannot send friend request while blocked"
        )
    if row is None:
        p1, p2 = _pair(current_user_id, target_user_id)
        row = UserUser(
            user_id1=p1,
            user_id2=p2,
            relationship_type="friend_pending",
            action_user_id=current_user_id,
            created_at=now,
            updated_at=now,
        )
    else:
        row.relationship_type = "friend_pending"
        row.action_user_id = current_user_id
        row.updated_at = now
    session.add(row)
    session.add(
        UserNotification(
            user_id=target_user_id,
            type=UserNotificationType.FRIEND_REQUEST_RECEIVED,
            actor_user_id=current_user_id,
        )
    )
    session.commit()
    session.refresh(row)
    return to_relationship_response(target_user_id, row)


def accept_friend_request(
    session: Session,
    *,
    current_user_id: int,
    target_user_id: int,
) -> UserRelationshipResponse:
    require_target(session, current_user_id, target_user_id)
    row = get_relationship_row(session, current_user_id, target_user_id)
    if (
        row is None
        or row.relationship_type != "friend_pending"
        or row.action_user_id == current_user_id
    ):
        raise HTTPException(status_code=404, detail="No incoming friend request found")
    now = _utc_now()
    row.relationship_type = "friend"
    row.action_user_id = current_user_id
    row.updated_at = now
    session.add(row)
    session.add(
        UserNotification(
            user_id=target_user_id,
            type=UserNotificationType.FRIEND_REQUEST_ACCEPTED,
            actor_user_id=current_user_id,
        )
    )
    session.commit()
    session.refresh(row)
    return to_relationship_response(target_user_id, row)


def reject_friend_request(
    session: Session,
    *,
    current_user_id: int,
    target_user_id: int,
) -> UserRelationshipResponse:
    require_target(session, current_user_id, target_user_id)
    row = get_relationship_row(session, current_user_id, target_user_id)
    if (
        row is None
        or row.relationship_type != "friend_pending"
        or row.action_user_id == current_user_id
    ):
        raise HTTPException(status_code=404, detail="No incoming friend request found")
    session.delete(row)
    session.commit()
    return UserRelationshipResponse(
        target_user_id=target_user_id, relationship_type="none"
    )


def cancel_friend_request(
    session: Session,
    *,
    current_user_id: int,
    target_user_id: int,
) -> UserRelationshipResponse:
    require_target(session, current_user_id, target_user_id)
    row = get_relationship_row(session, current_user_id, target_user_id)
    if (
        row is None
        or row.relationship_type != "friend_pending"
        or row.action_user_id != current_user_id
    ):
        raise HTTPException(status_code=404, detail="No outgoing friend request found")
    session.delete(row)
    session.commit()
    return UserRelationshipResponse(
        target_user_id=target_user_id, relationship_type="none"
    )


def remove_friend(
    session: Session,
    *,
    current_user_id: int,
    target_user_id: int,
) -> UserRelationshipResponse:
    require_target(session, current_user_id, target_user_id)
    row = get_relationship_row(session, current_user_id, target_user_id)
    if row is None or row.relationship_type != "friend":
        raise HTTPException(status_code=404, detail="No friendship found")
    session.delete(row)
    session.commit()
    return UserRelationshipResponse(
        target_user_id=target_user_id, relationship_type="none"
    )


def list_friends(
    session: Session,
    *,
    current_user_id: int,
    offset: int = 0,
    limit: int = 5,
) -> LeaderboardResponse:
    rows = session.exec(
        select(UserUser).where(
            UserUser.relationship_type == "friend",
            or_(
                UserUser.user_id1 == current_user_id,
                UserUser.user_id2 == current_user_id,
            ),
        )
    ).all()

    friend_ids: list[int] = []
    for row in rows:
        friend_ids.append(
            row.user_id2 if row.user_id1 == current_user_id else row.user_id1
        )

    friends: list[User] = []
    if friend_ids:
        friends = list(
            session.exec(
                select(User).where(User.id.in_(friend_ids)).order_by(User.username.asc())
            ).all()
        )

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
