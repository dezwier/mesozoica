"""Schemas for user-user relationships."""

from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel


class UserRelationshipActionRequest(BaseModel):
    target_user_id: int


class UserRelationshipResponse(BaseModel):
    target_user_id: int
    relationship_type: str
    action_user_id: int | None = None
    created_at: datetime | None = None
    updated_at: datetime | None = None


class LeaderboardEntry(BaseModel):
    user: "UserResponse"
    count: int = 0
    rank: int = 0


class LeaderboardResponse(BaseModel):
    entries: list[LeaderboardEntry]
    total: int
    page: int = 1
    page_size: int = 5
    total_pages: int = 0


from app.schemas.auth import UserResponse  # noqa: E402

LeaderboardEntry.model_rebuild()
