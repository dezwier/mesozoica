"""Tests for tool read API and ownership collection."""

from sqlmodel import Session, select

from app.core.security import create_access_token
from app.models.tool import Tool
from app.models.tool_type import ToolType
from app.models.user import User
from app.models.user_tool import USER_TOOL_ACTION_OWNED, UserTool


def _seed_tool(session: Session, *, name: str = "Orbit Survey") -> ToolType:
    row = ToolType(
        name=name,
        category="1 site_discovery",
        scientific_tool="satellite imagery",
        description="Identifies exposed formations.",
        rarity=2,
        main_image_url="https://example.com/media/tools/Orbit Survey.png",
    )
    session.add(row)
    session.commit()
    session.refresh(row)
    return row


def _user(
    session: Session,
    *,
    username: str = "player",
    is_admin: bool = False,
) -> User:
    user = User(
        username=username,
        email=f"{username}@example.com",
        password="x",
        is_admin=is_admin,
    )
    session.add(user)
    session.commit()
    session.refresh(user)
    return user


def _auth_headers(user: User) -> dict[str, str]:
    token = create_access_token({"sub": str(user.id)})
    return {"Authorization": f"Bearer {token}"}


def _grant(
    session: Session, *, user_id: int, tool_id: int, level: int = 1
) -> Tool:
    """Grant ownership of catalog tool_type ``tool_id`` via instance + owned event."""
    instance = Tool(tool_type_id=tool_id, level=level)
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


def test_list_tools_anonymous_empty(client, session):
    _seed_tool(session)
    response = client.get("/api/v1/tools", params={"sort": "name"})
    assert response.status_code == 200
    body = response.json()
    assert body["items"] == []
    assert body["total"] == 0


def test_list_tools_owned_only(client, session):
    owned = _seed_tool(session, name="Orbit Survey")
    _seed_tool(session, name="Geo Hammer")
    user = _user(session)
    _grant(session, user_id=int(user.id), tool_id=int(owned.id))

    response = client.get(
        "/api/v1/tools",
        params={"sort": "name"},
        headers=_auth_headers(user),
    )
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 1
    item = body["items"][0]
    assert item["name"] == "Orbit Survey"
    assert item["level"] == 1
    assert item["spawn_date"] is not None


def test_list_tools_catalog_allows_non_admin(client, session):
    owned = _seed_tool(session, name="Orbit Survey")
    other = _seed_tool(session, name="Geo Hammer")
    user = _user(session, is_admin=False)
    _grant(session, user_id=int(user.id), tool_id=int(owned.id), level=1)

    response = client.get(
        "/api/v1/tools",
        params={"sort": "name", "mode": "catalog"},
        headers=_auth_headers(user),
    )
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 2
    by_name = {item["name"]: item for item in body["items"]}
    assert by_name["Orbit Survey"]["level"] == 1
    assert by_name["Geo Hammer"]["id"] == other.id
    assert by_name["Geo Hammer"]["level"] is None


def test_list_tools_show_all_admin(client, session):
    owned = _seed_tool(session, name="Orbit Survey")
    other = _seed_tool(session, name="Geo Hammer")
    admin = _user(session, username="admin", is_admin=True)
    _grant(session, user_id=int(admin.id), tool_id=int(owned.id), level=2)

    response = client.get(
        "/api/v1/tools",
        params={"sort": "name", "show_all": True, "mode": "catalog"},
        headers=_auth_headers(admin),
    )
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 2
    by_name = {item["name"]: item for item in body["items"]}
    assert by_name["Orbit Survey"]["level"] == 2
    assert by_name["Geo Hammer"]["level"] is None
    assert by_name["Geo Hammer"]["id"] == other.id


def test_list_tools_returns_summary_fields(client, session):
    row = _seed_tool(session)
    admin = _user(session, username="admin", is_admin=True)

    response = client.get(
        "/api/v1/tools",
        params={"sort": "name", "show_all": True, "mode": "catalog"},
        headers=_auth_headers(admin),
    )
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 1
    item = body["items"][0]
    assert item["id"] == row.id
    assert item["name"] == "Orbit Survey"
    assert item["scientific_tool"] == "satellite imagery"
    assert item["category"] == "1 site_discovery"
    assert item["rarity"] == 2
    assert item["description"] == "Identifies exposed formations."
    assert item["action"] == "Use"
    assert item["level"] is None
    assert item["spawn_date"] is None


def test_get_tool_by_id(client, session):
    row = _seed_tool(session)

    response = client.get(f"/api/v1/tools/{row.id}")
    assert response.status_code == 200
    item = response.json()
    assert item["name"] == "Orbit Survey"
    assert item["level"] is None


def test_get_tool_not_found(client):
    response = client.get("/api/v1/tools/9999")
    assert response.status_code == 404


def test_list_tools_search(client, session):
    _seed_tool(session)
    session.add(
        ToolType(
            name="Geo Hammer",
            category="4 excavation",
            scientific_tool="geological hammer",
            description="Splits rock.",
            rarity=1,
        )
    )
    session.commit()
    admin = _user(session, username="admin", is_admin=True)

    response = client.get(
        "/api/v1/tools",
        params={"q": "satellite", "sort": "name", "show_all": True, "mode": "catalog"},
        headers=_auth_headers(admin),
    )
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 1
    assert body["items"][0]["name"] == "Orbit Survey"


def test_list_tools_random_requires_seed(client, session):
    _seed_tool(session)
    admin = _user(session, username="admin", is_admin=True)
    response = client.get(
        "/api/v1/tools",
        params={"sort": "random", "show_all": True, "mode": "catalog"},
        headers=_auth_headers(admin),
    )
    assert response.status_code == 400


def test_list_tools_category_requires_seed(client, session):
    _seed_tool(session)
    admin = _user(session, username="admin", is_admin=True)
    response = client.get(
        "/api/v1/tools",
        params={"sort": "category", "show_all": True, "mode": "catalog"},
        headers=_auth_headers(admin),
    )
    assert response.status_code == 400


def test_list_tools_sort_by_category_sequence(client, session):
    session.add(
        ToolType(
            name="Zeta Tool",
            category="10 reconstruction",
            scientific_tool="z",
            description="Z.",
            rarity=1,
        )
    )
    session.add(
        ToolType(
            name="Alpha Tool",
            category="2 fossil_discovery",
            scientific_tool="a",
            description="A.",
            rarity=1,
        )
    )
    session.add(
        ToolType(
            name="Beta Tool",
            category="2 fossil_discovery",
            scientific_tool="b",
            description="B.",
            rarity=1,
        )
    )
    session.commit()
    admin = _user(session, username="admin", is_admin=True)

    response = client.get(
        "/api/v1/tools",
        params={"sort": "category", "seed": "stable", "show_all": True, "mode": "catalog"},
        headers=_auth_headers(admin),
    )
    assert response.status_code == 200
    items = response.json()["items"]
    categories = [item["category"] for item in items]
    assert categories == [
        "2 fossil_discovery",
        "2 fossil_discovery",
        "10 reconstruction",
    ]
    names_in_cat2 = [item["name"] for item in items if item["category"].startswith("2 ")]
    assert set(names_in_cat2) == {"Alpha Tool", "Beta Tool"}


def test_list_tools_filter_by_category(client, session):
    _seed_tool(session)
    session.add(
        ToolType(
            name="Geo Hammer",
            category="4 excavation",
            scientific_tool="geological hammer",
            description="Splits rock.",
            rarity=1,
        )
    )
    session.commit()
    admin = _user(session, username="admin", is_admin=True)

    response = client.get(
        "/api/v1/tools",
        params=[
            ("sort", "name"),
            ("category", "4 excavation"),
            ("show_all", "true"),
            ("mode", "catalog"),
        ],
        headers=_auth_headers(admin),
    )
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 1
    assert body["items"][0]["name"] == "Geo Hammer"


def test_list_tool_categories_owned_only(client, session):
    owned = ToolType(
        name="Zeta Tool",
        category="10 reconstruction",
        scientific_tool="z",
        description="Z.",
        rarity=1,
    )
    session.add(owned)
    session.add(
        ToolType(
            name="Alpha Tool",
            category="2 fossil_discovery",
            scientific_tool="a",
            description="A.",
            rarity=1,
        )
    )
    session.commit()
    session.refresh(owned)
    user = _user(session)
    _grant(session, user_id=int(user.id), tool_id=int(owned.id))

    response = client.get(
        "/api/v1/tools/categories",
        headers=_auth_headers(user),
    )
    assert response.status_code == 200
    assert response.json()["items"] == [
        {"value": "10 reconstruction", "label": "Reconstruction"},
    ]


def test_list_tool_categories_show_all(client, session):
    session.add(
        ToolType(
            name="Zeta Tool",
            category="10 reconstruction",
            scientific_tool="z",
            description="Z.",
            rarity=1,
        )
    )
    session.add(
        ToolType(
            name="Alpha Tool",
            category="2 fossil_discovery",
            scientific_tool="a",
            description="A.",
            rarity=1,
        )
    )
    session.commit()
    admin = _user(session, username="admin", is_admin=True)

    response = client.get(
        "/api/v1/tools/categories",
        params={"show_all": True, "mode": "catalog"},
        headers=_auth_headers(admin),
    )
    assert response.status_code == 200
    items = response.json()["items"]
    assert items == [
        {"value": "2 fossil_discovery", "label": "Fossil Discovery"},
        {"value": "10 reconstruction", "label": "Reconstruction"},
    ]


def test_collect_tool_creates_user_tool(client, session):
    tool = _seed_tool(session)
    admin = _user(session, username="admin", is_admin=True)

    response = client.post(
        f"/api/v1/tools/{tool.id}/collect",
        headers=_auth_headers(admin),
        json={"version": "Original"},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["id"] == tool.id
    assert body["level"] == 1

    events = session.exec(select(UserTool)).all()
    assert len(events) == 1
    assert events[0].user_id == admin.id
    assert events[0].action == USER_TOOL_ACTION_OWNED
    instance = session.get(Tool, events[0].tool_id)
    assert instance is not None
    assert instance.tool_type_id == tool.id
    assert instance.level == 1
    assert instance.version == "Original"


def test_collect_tool_allows_duplicate_with_version(client, session, tmp_path, monkeypatch):
    import app.core.config as config_module

    tools_root = tmp_path / "tools"
    (tools_root / "Original").mkdir(parents=True)
    (tools_root / "Summer 26").mkdir(parents=True)
    (tools_root / "Original" / "meta.yaml").write_text(
        "run_date: '2025-01-01T00:00:00+00:00'\nprompt: p\n", encoding="utf-8"
    )
    (tools_root / "Summer 26" / "meta.yaml").write_text(
        "run_date: '2026-01-01T00:00:00+00:00'\nprompt: p\n", encoding="utf-8"
    )
    monkeypatch.setattr(config_module.settings, "tool_images_dir", str(tools_root))

    tool = _seed_tool(session)
    admin = _user(session, username="admin", is_admin=True)
    _grant(session, user_id=int(admin.id), tool_id=int(tool.id), level=3)

    response = client.post(
        f"/api/v1/tools/{tool.id}/collect",
        headers=_auth_headers(admin),
        json={"version": "Summer 26"},
    )
    assert response.status_code == 200
    assert response.json()["level"] == 3

    events = session.exec(select(UserTool)).all()
    assert len(events) == 2
    instances = [session.get(Tool, e.tool_id) for e in events]
    versions = {i.version for i in instances if i is not None}
    assert "Summer 26" in versions


def test_collect_tool_requires_version(client, session):
    tool = _seed_tool(session)
    admin = _user(session, username="admin", is_admin=True)

    response = client.post(
        f"/api/v1/tools/{tool.id}/collect",
        headers=_auth_headers(admin),
        json={},
    )
    assert response.status_code == 422


def test_collect_tool_requires_admin(client, session):
    tool = _seed_tool(session)
    user = _user(session, is_admin=False)
    response = client.post(
        f"/api/v1/tools/{tool.id}/collect",
        headers=_auth_headers(user),
        json={"version": "Original"},
    )
    assert response.status_code == 403
