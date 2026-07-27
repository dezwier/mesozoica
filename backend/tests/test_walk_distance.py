"""Walk distance sync API tests."""

from __future__ import annotations

from datetime import date, datetime, timedelta, timezone

from fastapi.testclient import TestClient
from sqlmodel import Session

from app.models.user import User


def _register_user(client: TestClient, username: str, email: str) -> dict:
    response = client.post(
        "/api/v1/auth/register",
        json={
            "username": username,
            "email": email,
            "password": "secret123",
            "full_name": "Dr. Walk",
        },
    )
    assert response.status_code == 201
    return response.json()


def test_profile_includes_distance_fields(client: TestClient):
    registered = _register_user(client, "dist_user", "dist@example.com")
    response = client.get(
        "/api/v1/users/me",
        headers={"Authorization": f"Bearer {registered['access_token']}"},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["total_distance_m"] == 0.0
    assert body["weekly_distance_m"] == 0.0
    assert body["active_distance_m"] == 0.0
    assert body["active_weekly_distance_m"] == 0.0
    assert body["distance_week_start"] is None
    assert body["created_at"]


def test_patch_distance_grows_monotonically(client: TestClient):
    registered = _register_user(client, "walker", "walker@example.com")
    headers = {"Authorization": f"Bearer {registered['access_token']}"}
    week = "2026-07-20"  # Monday

    first = client.patch(
        "/api/v1/users/me/distance",
        headers=headers,
        json={
            "total_distance_m": 5000,
            "weekly_distance_m": 1200,
            "active_distance_m": 3000,
            "active_weekly_distance_m": 800,
            "week_start": week,
        },
    )
    assert first.status_code == 200
    assert first.json()["total_distance_m"] == 5000
    assert first.json()["weekly_distance_m"] == 1200
    assert first.json()["active_distance_m"] == 3000
    assert first.json()["active_weekly_distance_m"] == 800
    assert first.json()["distance_week_start"] == week

    # Downward totals are ignored; weekly same week takes max.
    second = client.patch(
        "/api/v1/users/me/distance",
        headers=headers,
        json={
            "total_distance_m": 4000,
            "weekly_distance_m": 800,
            "active_distance_m": 2000,
            "active_weekly_distance_m": 400,
            "week_start": week,
        },
    )
    assert second.status_code == 200
    assert second.json()["total_distance_m"] == 5000
    assert second.json()["weekly_distance_m"] == 1200
    assert second.json()["active_distance_m"] == 3000
    assert second.json()["active_weekly_distance_m"] == 800

    third = client.patch(
        "/api/v1/users/me/distance",
        headers=headers,
        json={
            "total_distance_m": 5500,
            "weekly_distance_m": 1500,
            "active_distance_m": 3200,
            "active_weekly_distance_m": 900,
            "week_start": week,
        },
    )
    assert third.status_code == 200
    assert third.json()["total_distance_m"] == 5500
    assert third.json()["weekly_distance_m"] == 1500
    assert third.json()["active_distance_m"] == 3200
    assert third.json()["active_weekly_distance_m"] == 900


def test_patch_distance_week_rollover(client: TestClient):
    registered = _register_user(client, "week_roll", "weekroll@example.com")
    headers = {"Authorization": f"Bearer {registered['access_token']}"}

    client.patch(
        "/api/v1/users/me/distance",
        headers=headers,
        json={
            "total_distance_m": 10000,
            "weekly_distance_m": 3000,
            "active_distance_m": 7000,
            "active_weekly_distance_m": 2000,
            "week_start": "2026-07-13",
        },
    )
    rolled = client.patch(
        "/api/v1/users/me/distance",
        headers=headers,
        json={
            "total_distance_m": 10500,
            "weekly_distance_m": 200,
            "active_distance_m": 7100,
            "active_weekly_distance_m": 100,
            "week_start": "2026-07-20",
        },
    )
    assert rolled.status_code == 200
    body = rolled.json()
    assert body["total_distance_m"] == 10500
    assert body["weekly_distance_m"] == 200
    assert body["active_distance_m"] == 7100
    assert body["active_weekly_distance_m"] == 100
    assert body["distance_week_start"] == "2026-07-20"


def test_patch_distance_ignores_stale_older_week(client: TestClient):
    registered = _register_user(client, "stale_week", "staleweek@example.com")
    headers = {"Authorization": f"Bearer {registered['access_token']}"}

    client.patch(
        "/api/v1/users/me/distance",
        headers=headers,
        json={
            "total_distance_m": 5000,
            "weekly_distance_m": 400,
            "active_distance_m": 3000,
            "active_weekly_distance_m": 200,
            "week_start": "2026-07-20",
        },
    )
    stale = client.patch(
        "/api/v1/users/me/distance",
        headers=headers,
        json={
            "total_distance_m": 5100,
            "weekly_distance_m": 9000,
            "active_distance_m": 3100,
            "active_weekly_distance_m": 8000,
            "week_start": "2026-07-13",
        },
    )
    assert stale.status_code == 200
    body = stale.json()
    assert body["total_distance_m"] == 5100
    assert body["weekly_distance_m"] == 400
    assert body["active_weekly_distance_m"] == 200
    assert body["distance_week_start"] == "2026-07-20"


def test_patch_distance_reset_weekly_heals_same_week(client: TestClient):
    registered = _register_user(client, "week_heal", "weekheal@example.com")
    headers = {"Authorization": f"Bearer {registered['access_token']}"}
    week = "2026-07-20"

    client.patch(
        "/api/v1/users/me/distance",
        headers=headers,
        json={
            "total_distance_m": 8000,
            "weekly_distance_m": 8000,
            "active_distance_m": 5000,
            "active_weekly_distance_m": 5000,
            "week_start": week,
        },
    )
    healed = client.patch(
        "/api/v1/users/me/distance",
        headers=headers,
        json={
            "total_distance_m": 8100,
            "weekly_distance_m": 100,
            "active_distance_m": 5100,
            "active_weekly_distance_m": 100,
            "week_start": week,
            "reset_weekly": True,
        },
    )
    assert healed.status_code == 200
    body = healed.json()
    assert body["weekly_distance_m"] == 100
    assert body["active_weekly_distance_m"] == 100
    assert body["active_distance_m"] == 5100
    assert body["distance_week_start"] == week


def test_patch_distance_rejects_absurd_jump(client: TestClient, session: Session):
    registered = _register_user(client, "spiky", "spiky@example.com")
    user_id = registered["user"]["id"]
    user = session.get(User, user_id)
    assert user is not None
    user.total_distance_m = 1000.0
    user.weekly_distance_m = 100.0
    user.distance_week_start = date(2026, 7, 20)
    user.distance_synced_at = datetime.now(timezone.utc) - timedelta(hours=1)
    session.add(user)
    session.commit()

    response = client.patch(
        "/api/v1/users/me/distance",
        headers={"Authorization": f"Bearer {registered['access_token']}"},
        json={
            "total_distance_m": 1_000_000,
            "weekly_distance_m": 900_000,
            "week_start": "2026-07-20",
        },
    )
    assert response.status_code == 400
