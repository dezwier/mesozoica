"""Auth, profile, and friends API tests."""

from __future__ import annotations

from fastapi.testclient import TestClient
from sqlmodel import Session

from app.core.security import create_access_token
from app.models.user import User


def _auth_headers(user_id: int) -> dict[str, str]:
    token = create_access_token({"sub": str(user_id)})
    return {"Authorization": f"Bearer {token}"}


def _register_user(client: TestClient, username: str, email: str) -> dict:
    response = client.post(
        "/api/v1/auth/register",
        json={
            "username": username,
            "email": email,
            "password": "secret123",
            "full_name": "Dr. Rex",
        },
    )
    assert response.status_code == 201
    return response.json()


def test_register_and_login(client: TestClient):
    registered = _register_user(client, "rex", "rex@example.com")
    assert registered["access_token"]
    assert registered["user"]["username"] == "rex"
    assert registered["user"]["display_name"] == "Dr. Rex"

    login = client.post(
        "/api/v1/auth/login",
        json={"username": "rex", "password": "secret123"},
    )
    assert login.status_code == 200
    assert login.json()["user"]["email"] == "rex@example.com"


def test_get_my_profile(client: TestClient):
    registered = _register_user(client, "profile_user", "profile@example.com")
    token = registered["access_token"]
    response = client.get(
        "/api/v1/users/me",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["username"] == "profile_user"
    assert body["actual_dinosaurs_count"] == 0


def test_users_list_and_friend_flow(client: TestClient, session: Session):
    user_a = _register_user(client, "alice", "alice@example.com")
    user_b = _register_user(client, "bob", "bob@example.com")

    list_response = client.get(
        "/api/v1/users/list",
        headers={"Authorization": f"Bearer {user_a['access_token']}"},
    )
    assert list_response.status_code == 200
    assert list_response.json()["total"] >= 2

    bob_id = user_b["user"]["id"]
    request_response = client.post(
        "/api/v1/user-relationships/friend-request",
        headers={"Authorization": f"Bearer {user_a['access_token']}"},
        json={"target_user_id": bob_id},
    )
    assert request_response.status_code == 200
    assert request_response.json()["relationship_type"] == "friend_pending"

    rel = client.get(
        f"/api/v1/user-relationships/{bob_id}",
        headers={"Authorization": f"Bearer {user_a['access_token']}"},
    )
    assert rel.status_code == 200
    assert rel.json()["relationship_type"] == "friend_pending"

    # Promote to friend directly in DB for test simplicity
    from app.models.user_user import UserUser

    row = session.exec(
        __import__("sqlmodel").select(UserUser).where(
            UserUser.relationship_type == "friend_pending"
        )
    ).first()
    assert row is not None
    row.relationship_type = "friend"
    session.add(row)
    session.commit()

    friends = client.get(
        "/api/v1/user-relationships/friends/me/list",
        headers={"Authorization": f"Bearer {user_a['access_token']}"},
    )
    assert friends.status_code == 200
    assert friends.json()["total"] == 1


def test_get_self_relationship(client: TestClient):
    registered = _register_user(client, "self_user", "self@example.com")
    user_id = registered["user"]["id"]
    response = client.get(
        f"/api/v1/user-relationships/{user_id}",
        headers={"Authorization": f"Bearer {registered['access_token']}"},
    )
    assert response.status_code == 200
    assert response.json()["relationship_type"] == "self"


def test_public_profile(client: TestClient):
    registered = _register_user(client, "public_user", "public@example.com")
    user_id = registered["user"]["id"]
    other = _register_user(client, "viewer", "viewer@example.com")
    response = client.get(
        f"/api/v1/users/{user_id}/profile",
        headers={"Authorization": f"Bearer {other['access_token']}"},
    )
    assert response.status_code == 200
    assert response.json()["username"] == "public_user"


def test_update_profile_username(client: TestClient):
    registered = _register_user(client, "oldname", "old@example.com")
    token = registered["access_token"]
    response = client.patch(
        "/api/v1/auth/update-profile",
        headers={"Authorization": f"Bearer {token}"},
        json={"full_name": "Old Name Updated"},
    )
    assert response.status_code == 200
    assert response.json()["user"]["full_name"] == "Old Name Updated"
