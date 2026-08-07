"""Notifications endpoints and friend-request notification flow."""

from __future__ import annotations

from fastapi.testclient import TestClient

from app.features.accounts.infrastructure import push


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


def test_get_notifications_requires_auth(client: TestClient):
    response = client.get("/api/v1/notifications")
    assert response.status_code in (401, 403)


def test_get_notifications_with_auth_returns_200(client: TestClient):
    registered = _register_user(client, "notif_user", "notif@example.com")
    response = client.get(
        "/api/v1/notifications",
        headers={"Authorization": f"Bearer {registered['access_token']}"},
    )
    assert response.status_code == 200
    data = response.json()
    assert "notifications" in data
    assert isinstance(data["notifications"], list)


def test_mark_notification_read_not_found_returns_404(client: TestClient):
    registered = _register_user(client, "notif_read", "notif_read@example.com")
    response = client.patch(
        "/api/v1/notifications/999999/read",
        headers={"Authorization": f"Bearer {registered['access_token']}"},
    )
    assert response.status_code == 404


def test_site_identified_push_uses_standard_celebration_payload(monkeypatch):
    sent: list[dict] = []
    monkeypatch.setattr(push, "get_device_tokens", lambda session, user_id: ["token"])
    monkeypatch.setattr(
        push,
        "_get_unread_notification_badge_count",
        lambda session, user_id: 3,
    )
    monkeypatch.setattr(
        push,
        "send_push_to_tokens",
        lambda tokens, title, body, data, badge_count: sent.append(
            {
                "tokens": tokens,
                "title": title,
                "body": body,
                "data": data,
                "badge_count": badge_count,
            }
        )
        or [],
    )

    push.send_site_celebration_push(
        object(),
        user_id=7,
        site_id=99,
        notification_id=12,
        notification_type="site_identified",
        site_label="Morrison Formation",
    )

    assert sent == [
        {
            "tokens": ["token"],
            "title": "Mesozoica",
            "body": "Site identified: Morrison Formation",
            "data": {
                "type": "site_identified",
                "site_id": "99",
                "notification_id": "12",
            },
            "badge_count": 3,
        }
    ]


def test_mark_notification_read_syncs_unread_badge(client: TestClient, monkeypatch):
    registered = _register_user(client, "badge_sync", "badge_sync@example.com")
    token = registered["access_token"]
    user_id = registered["user"]["id"]

    other = _register_user(client, "badge_peer", "badge_peer@example.com")
    send = client.post(
        "/api/v1/user-relationships/friend-request",
        headers={"Authorization": f"Bearer {other['access_token']}"},
        json={"target_user_id": user_id},
    )
    assert send.status_code == 200

    items = client.get(
        "/api/v1/notifications",
        headers={"Authorization": f"Bearer {token}"},
    ).json()["notifications"]
    assert len(items) == 1
    notification_id = items[0]["id"]

    synced: list[int] = []

    def _fake_sync(session, uid: int) -> None:
        synced.append(uid)

    # Endpoint imports sync_unread_badge at call time from push_service.
    monkeypatch.setattr(
        "app.services.push_service.sync_unread_badge",
        _fake_sync,
    )

    mark_read = client.patch(
        f"/api/v1/notifications/{notification_id}/read",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert mark_read.status_code == 200
    assert synced == [user_id]


def test_friend_request_creates_notification_and_accept_notifies_requester(client: TestClient):
    user_a = _register_user(client, "alice_notif", "alice_notif@example.com")
    user_b = _register_user(client, "bob_notif", "bob_notif@example.com")
    bob_id = user_b["user"]["id"]
    alice_id = user_a["user"]["id"]

    send = client.post(
        "/api/v1/user-relationships/friend-request",
        headers={"Authorization": f"Bearer {user_a['access_token']}"},
        json={"target_user_id": bob_id},
    )
    assert send.status_code == 200

    bob_notifications = client.get(
        "/api/v1/notifications",
        headers={"Authorization": f"Bearer {user_b['access_token']}"},
    )
    assert bob_notifications.status_code == 200
    bob_items = bob_notifications.json()["notifications"]
    assert len(bob_items) == 1
    assert bob_items[0]["type"] == "friend_request_received"
    assert bob_items[0]["actor_user_id"] == alice_id
    assert bob_items[0]["actor_username"] == "alice_notif"
    assert bob_items[0]["read"] is False
    notification_id = bob_items[0]["id"]

    mark_read = client.patch(
        f"/api/v1/notifications/{notification_id}/read",
        headers={"Authorization": f"Bearer {user_b['access_token']}"},
    )
    assert mark_read.status_code == 200
    assert mark_read.json()["ok"] is True

    bob_notifications_after = client.get(
        "/api/v1/notifications",
        headers={"Authorization": f"Bearer {user_b['access_token']}"},
    )
    assert bob_notifications_after.json()["notifications"][0]["read"] is True

    accept = client.post(
        f"/api/v1/user-relationships/friend-request/{alice_id}/accept",
        headers={"Authorization": f"Bearer {user_b['access_token']}"},
    )
    assert accept.status_code == 200
    assert accept.json()["relationship_type"] == "friend"

    alice_notifications = client.get(
        "/api/v1/notifications",
        headers={"Authorization": f"Bearer {user_a['access_token']}"},
    )
    assert alice_notifications.status_code == 200
    alice_items = alice_notifications.json()["notifications"]
    assert len(alice_items) == 1
    assert alice_items[0]["type"] == "friend_request_accepted"
    assert alice_items[0]["actor_user_id"] == bob_id
    assert alice_items[0]["actor_username"] == "bob_notif"


def test_reject_friend_request(client: TestClient):
    user_a = _register_user(client, "reject_a", "reject_a@example.com")
    user_b = _register_user(client, "reject_b", "reject_b@example.com")
    bob_id = user_b["user"]["id"]
    alice_id = user_a["user"]["id"]

    client.post(
        "/api/v1/user-relationships/friend-request",
        headers={"Authorization": f"Bearer {user_a['access_token']}"},
        json={"target_user_id": bob_id},
    )

    reject = client.post(
        f"/api/v1/user-relationships/friend-request/{alice_id}/reject",
        headers={"Authorization": f"Bearer {user_b['access_token']}"},
    )
    assert reject.status_code == 200
    assert reject.json()["relationship_type"] == "none"

    rel = client.get(
        f"/api/v1/user-relationships/{alice_id}",
        headers={"Authorization": f"Bearer {user_b['access_token']}"},
    )
    assert rel.json()["relationship_type"] == "none"
