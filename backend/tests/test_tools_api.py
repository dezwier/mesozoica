"""Tests for tool read API."""

from sqlmodel import Session

from app.models.tool import Tool


def _seed_tool(session: Session) -> Tool:
    row = Tool(
        name="Orbit Survey",
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


def test_list_tools_empty(client):
    response = client.get("/api/v1/tools", params={"sort": "name"})
    assert response.status_code == 200
    body = response.json()
    assert body["items"] == []
    assert body["total"] == 0


def test_list_tools_returns_summary_fields(client, session):
    row = _seed_tool(session)

    response = client.get("/api/v1/tools", params={"sort": "name"})
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
            category="4 excavation",
            scientific_tool="geological hammer",
            description="Splits rock.",
            rarity=1,
        )
    )
    session.commit()

    response = client.get("/api/v1/tools", params={"q": "satellite", "sort": "name"})
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 1
    assert body["items"][0]["name"] == "Orbit Survey"


def test_list_tools_random_requires_seed(client, session):
    _seed_tool(session)
    response = client.get("/api/v1/tools", params={"sort": "random"})
    assert response.status_code == 400


def test_list_tools_category_requires_seed(client, session):
    _seed_tool(session)
    response = client.get("/api/v1/tools", params={"sort": "category"})
    assert response.status_code == 400


def test_list_tools_sort_by_category_sequence(client, session):
    session.add(
        Tool(
            name="Zeta Tool",
            category="10 reconstruction",
            scientific_tool="z",
            description="Z.",
            rarity=1,
        )
    )
    session.add(
        Tool(
            name="Alpha Tool",
            category="2 fossil_discovery",
            scientific_tool="a",
            description="A.",
            rarity=1,
        )
    )
    session.add(
        Tool(
            name="Beta Tool",
            category="2 fossil_discovery",
            scientific_tool="b",
            description="B.",
            rarity=1,
        )
    )
    session.commit()

    response = client.get(
        "/api/v1/tools",
        params={"sort": "category", "seed": "stable"},
    )
    assert response.status_code == 200
    items = response.json()["items"]
    categories = [item["category"] for item in items]
    assert categories == [
        "2 fossil_discovery",
        "2 fossil_discovery",
        "10 reconstruction",
    ]
    # Within category 2, order is seed-stable (not name A–Z).
    names_in_cat2 = [item["name"] for item in items if item["category"].startswith("2 ")]
    assert set(names_in_cat2) == {"Alpha Tool", "Beta Tool"}


def test_list_tools_filter_by_category(client, session):
    _seed_tool(session)
    session.add(
        Tool(
            name="Geo Hammer",
            category="4 excavation",
            scientific_tool="geological hammer",
            description="Splits rock.",
            rarity=1,
        )
    )
    session.commit()

    response = client.get(
        "/api/v1/tools",
        params=[
            ("sort", "name"),
            ("category", "4 excavation"),
        ],
    )
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 1
    assert body["items"][0]["name"] == "Geo Hammer"


def test_list_tool_categories(client, session):
    session.add(
        Tool(
            name="Zeta Tool",
            category="10 reconstruction",
            scientific_tool="z",
            description="Z.",
            rarity=1,
        )
    )
    session.add(
        Tool(
            name="Alpha Tool",
            category="2 fossil_discovery",
            scientific_tool="a",
            description="A.",
            rarity=1,
        )
    )
    session.commit()

    response = client.get("/api/v1/tools/categories")
    assert response.status_code == 200
    items = response.json()["items"]
    assert items == [
        {"value": "2 fossil_discovery", "label": "Fossil Discovery"},
        {"value": "10 reconstruction", "label": "Reconstruction"},
    ]
