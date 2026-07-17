"""Tests for tool read API."""

from sqlmodel import Session

from app.models.tool import Tool


def _seed_tool(session: Session) -> Tool:
    row = Tool(
        name="Orbit Survey",
        category="prospecting",
        scientific_tool="satellite imagery",
        description="Identifies exposed formations.",
        rarity=2,
        main_image_url="https://example.com/media/tools/Orbit Survey.png",
    )
    session.add(row)
    session.commit()
    session.refresh(row)
    return row


def test_list_tools_empty(client):
    response = client.get("/api/v1/tools")
    assert response.status_code == 200
    body = response.json()
    assert body["items"] == []
    assert body["total"] == 0


def test_list_tools_returns_summary_fields(client, session):
    row = _seed_tool(session)

    response = client.get("/api/v1/tools")
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 1
    item = body["items"][0]
    assert item["id"] == row.id
    assert item["name"] == "Orbit Survey"
    assert item["scientific_tool"] == "satellite imagery"
    assert item["category"] == "prospecting"
    assert item["rarity"] == 2
    assert item["description"] == "Identifies exposed formations."


def test_get_tool_by_id(client, session):
    row = _seed_tool(session)

    response = client.get(f"/api/v1/tools/{row.id}")
    assert response.status_code == 200
    item = response.json()
    assert item["name"] == "Orbit Survey"


def test_get_tool_not_found(client):
    response = client.get("/api/v1/tools/9999")
    assert response.status_code == 404


def test_list_tools_search(client, session):
    _seed_tool(session)
    session.add(
        Tool(
            name="Geo Hammer",
            category="excavation",
            scientific_tool="geological hammer",
            description="Splits rock.",
            rarity=1,
        )
    )
    session.commit()

    response = client.get("/api/v1/tools", params={"q": "satellite"})
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 1
    assert body["items"][0]["name"] == "Orbit Survey"


def test_list_tools_random_requires_seed(client, session):
    _seed_tool(session)
    response = client.get("/api/v1/tools", params={"sort": "random"})
    assert response.status_code == 400
