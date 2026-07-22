"""Walk-distance sync helpers (HealthKit / Health Connect → user profile)."""

from __future__ import annotations

from datetime import datetime, timezone

from fastapi import HTTPException, status
from sqlmodel import Session

from app.models.user import User
from app.schemas.auth import UpdateDistanceRequest, UserProfileResponse
from app.services.user_service import user_to_profile_response

# Cap reported growth vs last sync (~200 km/day) to blunt trivial tampering.
_MAX_METERS_PER_DAY = 200_000.0


def apply_distance_update(
    session: Session,
    user: User,
    payload: UpdateDistanceRequest,
) -> UserProfileResponse:
    now = datetime.now(timezone.utc)
    previous_total = float(user.total_distance_m or 0.0)
    previous_weekly = float(user.weekly_distance_m or 0.0)
    previous_week_start = user.distance_week_start
    previous_synced = user.distance_synced_at

    reported_total = float(payload.total_distance_m)
    reported_weekly = float(payload.weekly_distance_m)
    week_start = payload.week_start

    if reported_total < previous_total:
        # Distance only grows; ignore downward reports (stale device / reset).
        new_total = previous_total
    else:
        new_total = reported_total

    delta_total = new_total - previous_total
    if previous_synced is not None and delta_total > 0:
        synced = previous_synced
        if synced.tzinfo is None:
            synced = synced.replace(tzinfo=timezone.utc)
        elapsed_days = max((now - synced).total_seconds() / 86400.0, 1.0 / 24.0)
        max_delta = _MAX_METERS_PER_DAY * elapsed_days
        if delta_total > max_delta:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=(
                    "Distance increase exceeds the allowed rate "
                    f"({delta_total:.0f}m in {elapsed_days:.2f} days)."
                ),
            )

    if previous_week_start is None or week_start != previous_week_start:
        new_weekly = reported_weekly
    else:
        new_weekly = max(previous_weekly, reported_weekly)

    user.total_distance_m = new_total
    user.weekly_distance_m = new_weekly
    user.distance_week_start = week_start
    user.distance_synced_at = now
    session.add(user)
    session.commit()
    session.refresh(user)
    return user_to_profile_response(user)
