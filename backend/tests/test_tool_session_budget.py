"""Lifetime battery / tool-session history."""

from __future__ import annotations

from datetime import datetime, timedelta

from sqlmodel import Session, select

from app.core.game_config import get_game_config
from app.core.security import create_access_token
from app.models.tool import Tool
from app.models.tool_session import (
    ACTION_KEY_GEO_COMPASS,
    SESSION_STATUS_CANCELLED,
    SESSION_STATUS_COMPLETED,
    STOP_REASON_EXHAUSTED,
    STOP_REASON_MANUAL,
    ToolSession,
)
from app.models.tool_type import ToolType
from app.models.user import User
from app.models.user_tool import USER_TOOL_ACTION_OWNED, UserTool
from app.services.tool_action_service.tool_session import (
    cancel_timed_session,
    get_active_timed_session,
    remaining_duration_s,
    start_timed_session,
)


def _auth_headers(user: User) -> dict[str, str]:
    token = create_access_token({"sub": str(user.id)})
    return {"Authorization": f"Bearer {token}"}


def _user(session: Session, *, username: str = "budget") -> User:
    user = User(
        username=username,
        email=f"{username}@example.com",
        password="x",
    )
    session.add(user)
    session.commit()
    session.refresh(user)
    return user


def _tool(session: Session, *, name: str = "Geo Compass") -> ToolType:
    tool = ToolType(
        name=name,
        category="1 field_survey",
        scientific_tool="guidance",
        description="test",
        rarity=1,
        action="Consult",
    )
    session.add(tool)
    session.commit()
    session.refresh(tool)
    return tool


def _grant(
    session: Session,
    *,
    user_id: int,
    tool_id: int,
    params_json: dict | None = None,
) -> Tool:
    instance = Tool(
        tool_type_id=tool_id,
        level=1,
        params_json=params_json or {"duration_minutes": 10},
    )
    session.add(instance)
    session.flush()
    session.add(
        UserTool(
            user_id=user_id,
            tool_id=int(instance.id),
            action=USER_TOOL_ACTION_OWNED,
        )
    )
    session.commit()
    session.refresh(instance)
    return instance


def test_manual_stop_charges_elapsed_only(session: Session) -> None:
    get_game_config.cache_clear()
    user = _user(session)
    compass = _tool(session)
    instance = _grant(
        session,
        user_id=int(user.id),
        tool_id=int(compass.id),
        params_json={"duration_minutes": 10},
    )

    row = start_timed_session(
        session, user_id=int(user.id), tool_id=int(compass.id)
    )
    row.started_at = datetime.utcnow() - timedelta(minutes=3)
    session.add(row)
    session.commit()

    cancelled = cancel_timed_session(session, user_id=int(user.id))
    assert cancelled is not None
    assert cancelled.status == SESSION_STATUS_CANCELLED
    assert cancelled.stop_reason == STOP_REASON_MANUAL
    assert cancelled.used_duration_s is not None
    assert 170 <= cancelled.used_duration_s <= 200

    rem = remaining_duration_s(session, tool_type=compass, instance=instance)
    assert 400 <= rem <= 430  # ~7 minutes left of 10


def test_exhaustion_charges_full_allocation(session: Session) -> None:
    get_game_config.cache_clear()
    user = _user(session, username="exhaust")
    compass = _tool(session)
    instance = _grant(
        session,
        user_id=int(user.id),
        tool_id=int(compass.id),
        params_json={"duration_minutes": 5},
    )

    row = start_timed_session(
        session, user_id=int(user.id), tool_id=int(compass.id)
    )
    row.started_at = datetime.utcnow() - timedelta(minutes=6)
    row.expires_at = datetime.utcnow() - timedelta(minutes=1)
    session.add(row)
    session.commit()

    assert get_active_timed_session(session, user_id=int(user.id)) is None
    session.refresh(row)
    assert row.status == SESSION_STATUS_COMPLETED
    assert row.stop_reason == STOP_REASON_EXHAUSTED
    assert row.used_duration_s == 5 * 60

    rem = remaining_duration_s(session, tool_type=compass, instance=instance)
    assert rem == 0


def test_start_rejected_when_battery_empty(client, session: Session) -> None:
    get_game_config.cache_clear()
    user = _user(session, username="empty")
    compass = _tool(session)
    _grant(
        session,
        user_id=int(user.id),
        tool_id=int(compass.id),
        params_json={"duration_minutes": 5},
    )
    headers = _auth_headers(user)

    first = client.post(
        f"/api/v1/tools/{compass.id}/sessions",
        headers=headers,
    )
    assert first.status_code in (201, 202), first.text

    row = session.exec(select(ToolSession)).first()
    assert row is not None
    row.status = SESSION_STATUS_COMPLETED
    row.ended_at = datetime.utcnow()
    row.used_duration_s = 5 * 60
    row.stop_reason = STOP_REASON_EXHAUSTED
    session.add(row)
    session.commit()

    second = client.post(
        f"/api/v1/tools/{compass.id}/sessions",
        headers=headers,
    )
    assert second.status_code == 400
    assert "duration" in second.json()["detail"].lower()


def test_sessions_list_endpoint(client, session: Session) -> None:
    get_game_config.cache_clear()
    user = _user(session, username="uses")
    compass = _tool(session)
    instance = _grant(
        session,
        user_id=int(user.id),
        tool_id=int(compass.id),
        params_json={"duration_minutes": 15},
    )
    headers = _auth_headers(user)

    start = client.post(
        f"/api/v1/tools/{compass.id}/sessions",
        headers=headers,
    )
    assert start.status_code in (201, 202), start.text
    session_id = start.json()["session_id"]

    client.post(f"/api/v1/tools/sessions/{session_id}/cancel", headers=headers)

    resp = client.get(f"/api/v1/tools/{compass.id}/sessions", headers=headers)
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["tool_id"] == int(instance.id)
    assert body["total_duration_s"] == 15 * 60
    assert body["remaining_duration_s"] >= 0
    assert len(body["items"]) == 1
    item = body["items"][0]
    assert item["action_key"] == ACTION_KEY_GEO_COMPASS
    assert item["stop_reason"] == STOP_REASON_MANUAL
    assert (item["used_duration_s"] or 0) >= 0

    history = body["history"]
    assert len(history) == 2
    kinds = [entry["kind"] for entry in history]
    assert kinds.count("session") == 1
    assert kinds.count("role") == 1
    # Newest first.
    assert history[0]["at"] >= history[1]["at"]
    role = next(entry for entry in history if entry["kind"] == "role")
    assert role["role"]["action"] == "owned"
