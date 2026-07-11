"""Tests for dinosaur read API."""

from datetime import datetime, timezone

from sqlmodel import Session

from app.models.dinosaur import Dinosaur


def _seed_tyrannosaurus(session: Session) -> Dinosaur:
    row = Dinosaur(
        name="Tyrannosaurus",
        wikipedia_page_id=30467,
        wikipedia_title="Tyrannosaurus",
        birth=77.0,
        death=66.0,
        period="Late Cretaceous",
        cladogram={
            "kingdom": "Animalia",
            "clade": "Dinosauria",
            "order": "Saurischia",
            "genus": "Tyrannosaurus",
        },
        diet_type="carnivore",
        short_description="A towering Late Cretaceous apex predator.",
        long_description="Tyrannosaurus is a genus of large theropod dinosaur.",
        article="<p>html</p>",
        article_date=datetime(2026, 7, 8, tzinfo=timezone.utc),
        length="12 m",
        mass="7 t",
        location="North America",
        main_image_url="https://upload.wikimedia.org/wikipedia/commons/t-rex.jpg",
        llm_enriched=True,
    )
    session.add(row)
    session.commit()
    session.refresh(row)
    return row


def test_list_dinosaurs_empty(client):
    response = client.get("/api/v1/dinosaurs")
    assert response.status_code == 200
    body = response.json()
    assert body["items"] == []
    assert body["total"] == 0
    assert body["limit"] == 200
    assert body["offset"] == 0


def test_list_dinosaurs_returns_summary_fields(client, session):
    row = _seed_tyrannosaurus(session)

    response = client.get("/api/v1/dinosaurs")
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 1
    assert len(body["items"]) == 1

    item = body["items"][0]
    assert item["id"] == row.id
    assert item["name"] == "Tyrannosaurus"
    assert item["birth"] == 77.0
    assert item["death"] == 66.0
    assert item["cladogram"]["genus"] == "Tyrannosaurus"
    assert item["main_image_url"].endswith("t-rex.jpg")
    assert "article" not in item


def test_list_dinosaurs_pagination(client, session):
    for index, name in enumerate(["Brachiosaurus", "Stegosaurus", "Velociraptor"]):
        session.add(
            Dinosaur(
                name=name,
                wikipedia_page_id=1000 + index,
                wikipedia_title=name,
            )
        )
    session.commit()

    response = client.get("/api/v1/dinosaurs?limit=2&offset=1")
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 3
    assert body["limit"] == 2
    assert body["offset"] == 1
    assert len(body["items"]) == 2
    assert body["items"][0]["name"] == "Stegosaurus"


def test_get_dinosaur_by_id(client, session):
    row = _seed_tyrannosaurus(session)

    response = client.get(f"/api/v1/dinosaurs/{row.id}")
    assert response.status_code == 200
    body = response.json()
    assert body["name"] == "Tyrannosaurus"
    assert body["diet_type"] == "carnivore"


def test_get_dinosaur_not_found(client):
    response = client.get("/api/v1/dinosaurs/99999")
    assert response.status_code == 404
