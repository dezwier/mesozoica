"""Tests for dinosaur read API."""

from datetime import datetime, timezone

from sqlmodel import Session

from app.models.dinosaur_type import DinosaurType


def _seed_tyrannosaurus(session: Session) -> DinosaurType:
    row = DinosaurType(
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
    assert body["has_next"] is False


def test_list_dinosaurs_returns_summary_fields(client, session):
    row = _seed_tyrannosaurus(session)

    response = client.get("/api/v1/dinosaurs")
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 1
    assert len(body["items"]) == 1

    item = body["items"][0]
    assert item["id"] == row.id
    assert item["dinosaur_type_id"] == row.id
    assert item["name"] == "Tyrannosaurus"
    assert item["birth"] == 77.0
    assert item["death"] == 66.0
    assert item["cladogram"]["genus"] == "Tyrannosaurus"
    assert item["main_image_url"].endswith("t-rex.jpg")
    assert "article" not in item
    assert item["created_at"] is None


def test_list_dinosaurs_defaults_to_catalog_mode(client, session):
    _seed_tyrannosaurus(session)
    response = client.get("/api/v1/dinosaurs", params={"mode": "catalog", "sort": "name"})
    assert response.status_code == 200
    assert response.json()["total"] == 1


def test_list_dinosaurs_inventory_empty_without_occurrences(client, session):
    from app.core.security import create_access_token
    from app.models.user import User

    _seed_tyrannosaurus(session)
    user = User(
        username="dino-owner",
        email="dino@example.com",
        password="x",
    )
    session.add(user)
    session.commit()
    session.refresh(user)
    token = create_access_token({"sub": str(user.id)})

    response = client.get(
        "/api/v1/dinosaurs",
        params={"mode": "inventory", "sort": "name"},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.status_code == 200
    assert response.json()["total"] == 0
    assert response.json()["items"] == []


def test_list_dinosaurs_inventory_includes_created_at(client, session):
    from app.core.security import create_access_token
    from app.models.dinosaur import Dinosaur
    from app.models.user import User
    from app.models.user_dinosaur import USER_DINOSAUR_ROLE_MODELLED, UserDinosaur

    dino_type = _seed_tyrannosaurus(session)
    user = User(
        username="dino-collector",
        email="collector@example.com",
        password="x",
    )
    session.add(user)
    session.commit()
    session.refresh(user)

    occurrence = Dinosaur(dinosaur_type_id=int(dino_type.id))
    session.add(occurrence)
    session.commit()
    session.refresh(occurrence)
    session.add(
        UserDinosaur(
            user_id=int(user.id),
            dinosaur_id=int(occurrence.id),
            role=USER_DINOSAUR_ROLE_MODELLED,
        )
    )
    session.commit()

    token = create_access_token({"sub": str(user.id)})
    response = client.get(
        "/api/v1/dinosaurs",
        params={"mode": "inventory", "sort": "name"},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 1
    item = body["items"][0]
    assert item["id"] == occurrence.id
    assert item["dinosaur_type_id"] == dino_type.id
    assert item["created_at"] is not None
    assert item["status"] == "modelled"


def test_list_dinosaurs_catalog_owned_occurrences(client, session):
    from app.core.security import create_access_token
    from app.models.dinosaur import Dinosaur
    from app.models.user import User
    from app.models.user_dinosaur import USER_DINOSAUR_ROLE_MODELLED, UserDinosaur

    dino_type = _seed_tyrannosaurus(session)
    user = User(
        username="catalog-owner",
        email="catalog-owner@example.com",
        password="x",
    )
    session.add(user)
    session.commit()
    session.refresh(user)

    first = Dinosaur(dinosaur_type_id=int(dino_type.id), version="Original")
    second = Dinosaur(dinosaur_type_id=int(dino_type.id), version="Summer 26")
    session.add(first)
    session.add(second)
    session.commit()
    session.refresh(first)
    session.refresh(second)
    session.add(
        UserDinosaur(
            user_id=int(user.id),
            dinosaur_id=int(first.id),
            role=USER_DINOSAUR_ROLE_MODELLED,
        )
    )
    session.add(
        UserDinosaur(
            user_id=int(user.id),
            dinosaur_id=int(second.id),
            role=USER_DINOSAUR_ROLE_MODELLED,
        )
    )
    session.commit()

    token = create_access_token({"sub": str(user.id)})
    response = client.get(
        "/api/v1/dinosaurs",
        params={"mode": "catalog", "sort": "name"},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.status_code == 200
    item = response.json()["items"][0]
    assert item["status"] == "modelled"
    owned = item["owned_occurrences"]
    assert len(owned) == 2
    assert {row["id"] for row in owned} == {first.id, second.id}
    assert {row["version"] for row in owned} == {"Original", "Summer 26"}
    for row in owned:
        assert "main_image_url" in row


def test_list_dinosaurs_catalog_owned_occurrences_empty_without_links(
    client, session
):
    from app.core.security import create_access_token
    from app.models.user import User

    _seed_tyrannosaurus(session)
    user = User(
        username="catalog-empty",
        email="catalog-empty@example.com",
        password="x",
    )
    session.add(user)
    session.commit()
    session.refresh(user)
    token = create_access_token({"sub": str(user.id)})
    response = client.get(
        "/api/v1/dinosaurs",
        params={"mode": "catalog", "sort": "name"},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.status_code == 200
    item = response.json()["items"][0]
    assert item["owned_occurrences"] == []
    assert item["status"] == "hidden"


def test_collect_dinosaur_admin_flow(client, session):
    from app.core.security import create_access_token
    from app.models.user import User

    dino_type = _seed_tyrannosaurus(session)
    admin = User(
        username="dino_status_admin",
        email="dino_status_admin@example.com",
        password="x",
        is_admin=True,
    )
    non_admin = User(
        username="dino_status_user",
        email="dino_status_user@example.com",
        password="x",
        is_admin=False,
    )
    session.add(admin)
    session.add(non_admin)
    session.commit()
    session.refresh(admin)
    session.refresh(non_admin)
    admin_headers = {
        "Authorization": f"Bearer {create_access_token({'sub': str(admin.id)})}"
    }
    user_headers = {
        "Authorization": f"Bearer {create_access_token({'sub': str(non_admin.id)})}"
    }

    forbidden = client.post(
        f"/api/v1/dinosaurs/{dino_type.id}/collect",
        headers=user_headers,
        json={"status": "modelled", "version": "Original"},
    )
    assert forbidden.status_code == 403

    modelled = client.post(
        f"/api/v1/dinosaurs/{dino_type.id}/collect",
        headers=admin_headers,
        json={"status": "modelled", "version": "Original"},
    )
    assert modelled.status_code == 200
    assert modelled.json()["status"] == "modelled"
    assert modelled.json()["dinosaur_type_id"] == dino_type.id
    assert modelled.json()["created_at"] is not None
    assert modelled.json()["version"] == "Original"
    first_id = modelled.json()["id"]

    inventory = client.get(
        "/api/v1/dinosaurs",
        params={"mode": "inventory", "sort": "name"},
        headers=admin_headers,
    )
    assert inventory.status_code == 200
    assert inventory.json()["total"] == 1
    assert inventory.json()["items"][0]["id"] == first_id
    assert inventory.json()["items"][0]["status"] == "modelled"

    # Collect again creates a second occurrence.
    reconstructed = client.post(
        f"/api/v1/dinosaurs/{dino_type.id}/collect",
        headers=admin_headers,
        json={"status": "reconstructed", "version": "Original"},
    )
    assert reconstructed.status_code == 200
    assert reconstructed.json()["status"] == "reconstructed"
    assert reconstructed.json()["id"] != first_id

    inventory2 = client.get(
        "/api/v1/dinosaurs",
        params={"mode": "inventory", "sort": "name"},
        headers=admin_headers,
    )
    assert inventory2.json()["total"] == 2

    versions = client.get(
        "/api/v1/dinosaurs/image-versions",
        headers=admin_headers,
    )
    assert versions.status_code == 200
    assert "items" in versions.json()


def test_list_dinosaurs_pagination(client, session):
    for index, name in enumerate(["Brachiosaurus", "Stegosaurus", "Velociraptor"]):
        session.add(
            DinosaurType(
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


def test_list_dinosaurs_random_requires_seed(client, session):
    for index, name in enumerate(["Brachiosaurus", "Stegosaurus", "Velociraptor"]):
        session.add(
            DinosaurType(
                name=name,
                wikipedia_page_id=2000 + index,
                wikipedia_title=name,
            )
        )
    session.commit()

    response = client.get("/api/v1/dinosaurs?sort=random")
    assert response.status_code == 400


def test_list_dinosaurs_random_stable_order_with_seed(client, session):
    for index, name in enumerate(["Brachiosaurus", "Stegosaurus", "Velociraptor"]):
        session.add(
            DinosaurType(
                name=name,
                wikipedia_page_id=3000 + index,
                wikipedia_title=name,
            )
        )
    session.commit()

    seed = "test-seed-123"
    first = client.get(
        f"/api/v1/dinosaurs?sort=random&seed={seed}&limit=1&offset=0"
    ).json()
    second = client.get(
        f"/api/v1/dinosaurs?sort=random&seed={seed}&limit=1&offset=1"
    ).json()
    repeat = client.get(
        f"/api/v1/dinosaurs?sort=random&seed={seed}&limit=1&offset=0"
    ).json()

    assert first["items"][0]["name"] == repeat["items"][0]["name"]
    assert first["items"][0]["name"] != second["items"][0]["name"]
    assert first["has_next"] is True
    assert second["has_next"] is True


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


def test_get_dinosaur_article(client, session):
    row = _seed_tyrannosaurus(session)

    response = client.get(f"/api/v1/dinosaurs/{row.id}/article")
    assert response.status_code == 200
    body = response.json()
    assert body["id"] == row.id
    assert body["name"] == "Tyrannosaurus"
    assert body["wikipedia_title"] == "Tyrannosaurus"
    assert body["article"] == "<p>html</p>"
    assert body["article_date"] is not None


def test_get_dinosaur_article_not_found(client):
    response = client.get("/api/v1/dinosaurs/99999/article")
    assert response.status_code == 404


def test_get_dinosaur_article_empty_when_no_html(client, session):
    row = DinosaurType(
        name="EmptyArticle",
        wikipedia_page_id=999,
        wikipedia_title="EmptyArticle",
        article=None,
    )
    session.add(row)
    session.commit()
    session.refresh(row)

    response = client.get(f"/api/v1/dinosaurs/{row.id}/article")
    assert response.status_code == 200
    body = response.json()
    assert body["article"] is None


def _seed_timed_dinos(session: Session) -> None:
    """T-rex Cretaceous, Stegosaurus Jurassic, Brachiosaurus Jurassic."""
    session.add_all(
        [
            DinosaurType(
                name="Tyrannosaurus",
                wikipedia_page_id=4001,
                wikipedia_title="Tyrannosaurus",
                birth=77.0,
                death=66.0,
            ),
            DinosaurType(
                name="Stegosaurus",
                wikipedia_page_id=4002,
                wikipedia_title="Stegosaurus",
                birth=155.0,
                death=150.0,
            ),
            DinosaurType(
                name="Brachiosaurus",
                wikipedia_page_id=4003,
                wikipedia_title="Brachiosaurus",
                birth=154.0,
                death=153.0,
            ),
            DinosaurType(
                name="UnknownPeriod",
                wikipedia_page_id=4004,
                wikipedia_title="UnknownPeriod",
            ),
        ]
    )
    session.commit()


def test_list_dinosaurs_filter_by_name(client, session):
    _seed_timed_dinos(session)

    response = client.get("/api/v1/dinosaurs?q=saurus")
    assert response.status_code == 200
    body = response.json()
    names = {item["name"] for item in body["items"]}
    assert names == {"Tyrannosaurus", "Stegosaurus", "Brachiosaurus"}
    assert body["total"] == 3


def test_list_dinosaurs_filter_by_time_overlap(client, session):
    _seed_timed_dinos(session)

    response = client.get(
        "/api/v1/dinosaurs?ma_younger=70&ma_older=80&sort=name"
    )
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 1
    assert body["items"][0]["name"] == "Tyrannosaurus"


def test_list_dinosaurs_filter_excludes_missing_dates_when_narrowed(client, session):
    _seed_timed_dinos(session)

    response = client.get(
        "/api/v1/dinosaurs?ma_younger=66&ma_older=252&sort=name"
    )
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 4


def test_list_dinosaurs_filter_combined(client, session):
    _seed_timed_dinos(session)

    response = client.get(
        "/api/v1/dinosaurs?q=saurus&ma_younger=150&ma_older=160&sort=name"
    )
    assert response.status_code == 200
    body = response.json()
    names = {item["name"] for item in body["items"]}
    assert names == {"Tyrannosaurus", "Stegosaurus", "Brachiosaurus"}
    assert body["total"] == 3


def test_list_dinosaurs_search_ignores_time_filter_for_undated_rows(client, session):
    session.add(
        DinosaurType(
            name="Brachiosaurus",
            wikipedia_page_id=5001,
            wikipedia_title="Brachiosaurus",
        )
    )
    session.commit()

    response = client.get(
        "/api/v1/dinosaurs?q=brachiosaurus&ma_younger=150&ma_older=160&sort=name"
    )
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 1
    assert body["items"][0]["name"] == "Brachiosaurus"


def test_list_dinosaurs_filter_random_stable_with_seed(client, session):
    _seed_timed_dinos(session)

    seed = "filter-seed-456"
    first = client.get(
        f"/api/v1/dinosaurs?sort=random&seed={seed}&q=saurus&limit=1&offset=0"
    ).json()
    second = client.get(
        f"/api/v1/dinosaurs?sort=random&seed={seed}&q=saurus&limit=1&offset=1"
    ).json()
    repeat = client.get(
        f"/api/v1/dinosaurs?sort=random&seed={seed}&q=saurus&limit=1&offset=0"
    ).json()

    assert first["total"] == 3
    assert first["items"][0]["name"] == repeat["items"][0]["name"]
    assert first["items"][0]["name"] != second["items"][0]["name"]
    assert first["has_next"] is True


def test_list_dinosaurs_filter_ma_requires_both_params(client, session):
    response = client.get("/api/v1/dinosaurs?ma_younger=66")
    assert response.status_code == 400


def test_list_dinosaurs_filter_has_custom_image(client, session):
    session.add_all(
        [
            DinosaurType(
                name="Tyrannosaurus",
                wikipedia_page_id=6001,
                wikipedia_title="Tyrannosaurus",
                main_image_url="https://mesozoica-production.up.railway.app/media/dinosaurs/Tyrannosaurus.webp",
            ),
            DinosaurType(
                name="Stegosaurus",
                wikipedia_page_id=6002,
                wikipedia_title="Stegosaurus",
                main_image_url="https://upload.wikimedia.org/wikipedia/commons/stego.jpg",
            ),
            DinosaurType(
                name="Brachiosaurus",
                wikipedia_page_id=6003,
                wikipedia_title="Brachiosaurus",
            ),
        ]
    )
    session.commit()

    response = client.get("/api/v1/dinosaurs?has_custom_image=true&sort=name")
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 1
    assert body["items"][0]["name"] == "Tyrannosaurus"

    all_response = client.get("/api/v1/dinosaurs?sort=name")
    assert all_response.status_code == 200
    assert all_response.json()["total"] == 3


def test_list_dinosaurs_catalog_sorts_imaged_first_then_name(client, session):
    session.add_all(
        [
            DinosaurType(
                name="Zebraosaurus",
                wikipedia_page_id=7001,
                wikipedia_title="Zebraosaurus",
                main_image_url="https://mesozoica-production.up.railway.app/media/dinosaurs/Zebraosaurus.webp",
            ),
            DinosaurType(
                name="Allosaurus",
                wikipedia_page_id=7002,
                wikipedia_title="Allosaurus",
            ),
            DinosaurType(
                name="Stegosaurus",
                wikipedia_page_id=7003,
                wikipedia_title="Stegosaurus",
                main_image_url="https://mesozoica-production.up.railway.app/media/dinosaurs/Stegosaurus.webp",
            ),
            DinosaurType(
                name="Brachiosaurus",
                wikipedia_page_id=7004,
                wikipedia_title="Brachiosaurus",
                main_image_url="https://upload.wikimedia.org/wikipedia/commons/brachio.jpg",
            ),
        ]
    )
    session.commit()

    response = client.get(
        "/api/v1/dinosaurs",
        params={"mode": "catalog", "sort": "name"},
    )
    assert response.status_code == 200
    names = [item["name"] for item in response.json()["items"]]
    # Curated /media/dinosaurs/ first (alpha), then without curated image (alpha).
    assert names == [
        "Stegosaurus",
        "Zebraosaurus",
        "Allosaurus",
        "Brachiosaurus",
    ]


def test_list_dinosaurs_filter_llm_enriched(client, session):
    session.add_all(
        [
            DinosaurType(
                name="Tyrannosaurus",
                wikipedia_page_id=6101,
                wikipedia_title="Tyrannosaurus",
                llm_enriched=True,
            ),
            DinosaurType(
                name="Stegosaurus",
                wikipedia_page_id=6102,
                wikipedia_title="Stegosaurus",
                llm_enriched=False,
            ),
        ]
    )
    session.commit()

    response = client.get("/api/v1/dinosaurs?llm_enriched=true&sort=name")
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 1
    assert body["items"][0]["name"] == "Tyrannosaurus"

    response = client.get("/api/v1/dinosaurs?llm_enriched=false&sort=name")
    assert response.status_code == 200
    assert response.json()["total"] == 1
    assert response.json()["items"][0]["name"] == "Stegosaurus"


def test_list_dinosaurs_filter_diet(client, session):
    session.add_all(
        [
            DinosaurType(
                name="Tyrannosaurus",
                wikipedia_page_id=7101,
                wikipedia_title="Tyrannosaurus",
                diet_type="Carnivore",
            ),
            DinosaurType(
                name="Triceratops",
                wikipedia_page_id=7102,
                wikipedia_title="Triceratops",
                diet_type="herbivore",
            ),
            DinosaurType(
                name="Omnivorasaurus",
                wikipedia_page_id=7103,
                wikipedia_title="Omnivorasaurus",
                diet_type="omnivore",
            ),
        ]
    )
    session.commit()

    response = client.get(
        "/api/v1/dinosaurs",
        params=[("diet", "carnivore"), ("diet", "herbivore"), ("sort", "name")],
    )
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 2
    assert [item["name"] for item in body["items"]] == [
        "Triceratops",
        "Tyrannosaurus",
    ]


def test_list_dinosaurs_filter_length_and_mass(client, session):
    session.add_all(
        [
            DinosaurType(
                name="Tyrannosaurus",
                wikipedia_page_id=7201,
                wikipedia_title="Tyrannosaurus",
                length="12 m",
                mass="7 t",
            ),
            DinosaurType(
                name="Compsognathus",
                wikipedia_page_id=7202,
                wikipedia_title="Compsognathus",
                length="1 m",
                mass="3 kg",
            ),
            DinosaurType(
                name="Brachiosaurus",
                wikipedia_page_id=7203,
                wikipedia_title="Brachiosaurus",
                length="~20 – 25 m",
                mass="~30 – 50 tonnes",
            ),
            DinosaurType(
                name="Unknownosaurus",
                wikipedia_page_id=7204,
                wikipedia_title="Unknownosaurus",
                length=None,
                mass=None,
            ),
        ]
    )
    session.commit()

    response = client.get(
        "/api/v1/dinosaurs",
        params={
            "sort": "name",
            "length_m_min": 8,
            "length_m_max": 15,
        },
    )
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 1
    assert body["items"][0]["name"] == "Tyrannosaurus"

    response = client.get(
        "/api/v1/dinosaurs",
        params={
            "sort": "name",
            "mass_kg_min": 20000,
            "mass_kg_max": 60000,
        },
    )
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 1
    assert body["items"][0]["name"] == "Brachiosaurus"

    # Overlap: Brachiosaurus 20–25 m overlaps 22–40.
    response = client.get(
        "/api/v1/dinosaurs",
        params={
            "sort": "name",
            "length_m_min": 22,
            "length_m_max": 40,
        },
    )
    assert response.status_code == 200
    assert [item["name"] for item in response.json()["items"]] == ["Brachiosaurus"]


def test_list_dinosaurs_filter_diet_and_size_inventory(client, session):
    from app.core.security import create_access_token
    from app.models.dinosaur import Dinosaur
    from app.models.user import User
    from app.models.user_dinosaur import USER_DINOSAUR_ROLE_MODELLED, UserDinosaur

    carnivore = DinosaurType(
        name="Tyrannosaurus",
        wikipedia_page_id=7301,
        wikipedia_title="Tyrannosaurus",
        diet_type="carnivore",
        length="12 m",
        mass="7 t",
    )
    herbivore = DinosaurType(
        name="Triceratops",
        wikipedia_page_id=7302,
        wikipedia_title="Triceratops",
        diet_type="herbivore",
        length="9 m",
        mass="6 t",
    )
    session.add_all([carnivore, herbivore])
    session.commit()
    session.refresh(carnivore)
    session.refresh(herbivore)

    user = User(username="size-filter", email="size@example.com", password="x")
    session.add(user)
    session.commit()
    session.refresh(user)

    for dino_type in (carnivore, herbivore):
        occurrence = Dinosaur(dinosaur_type_id=int(dino_type.id))
        session.add(occurrence)
        session.commit()
        session.refresh(occurrence)
        session.add(
            UserDinosaur(
                user_id=int(user.id),
                dinosaur_id=int(occurrence.id),
                role=USER_DINOSAUR_ROLE_MODELLED,
            )
        )
    session.commit()

    token = create_access_token({"sub": str(user.id)})
    response = client.get(
        "/api/v1/dinosaurs",
        params={
            "mode": "inventory",
            "sort": "name",
            "diet": "carnivore",
            "length_m_min": 10,
            "length_m_max": 15,
            "mass_kg_min": 5000,
            "mass_kg_max": 10000,
        },
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 1
    assert body["items"][0]["name"] == "Tyrannosaurus"
