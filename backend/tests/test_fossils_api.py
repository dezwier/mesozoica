"""Tests for fossil read API."""

from decimal import Decimal

from sqlmodel import Session

from app.models.dinosaur import Dinosaur
from app.models.fossil import Fossil
from app.models.site import Site
from app.models.site_type import SiteType


def _seed_site_type(session: Session) -> SiteType:
    row = SiteType(
        period="cretaceous",
        rock_type="sandstone",
        main_image_url="https://mesozoica-production.up.railway.app/media/site-types/1.png",
    )
    session.add(row)
    session.commit()
    session.refresh(row)
    return row


def _seed_hell_creek_site(session: Session, site_type: SiteType) -> Site:
    row = Site(
        site_id=50001,
        latitude=Decimal("46.879700"),
        longitude=Decimal("-110.362600"),
        country_code="US",
        state="Montana",
        rock_type="sandstone",
        formation="Hell Creek Formation",
        min_age_ma=Decimal("66.00"),
        max_age_ma=Decimal("68.00"),
        site_type_id=site_type.id,
    )
    session.add(row)
    session.commit()
    session.refresh(row)
    return row


def _seed_tyrannosaurus(session: Session) -> Dinosaur:
    row = Dinosaur(
        name="Tyrannosaurus",
        wikipedia_page_id=30467,
        wikipedia_title="Tyrannosaurus",
        birth=77.0,
        death=66.0,
        main_image_url="https://mesozoica-production.up.railway.app/media/dinosaurs/Tyrannosaurus.webp",
    )
    session.add(row)
    session.commit()
    session.refresh(row)
    return row


def _seed_hell_creek_fossil(session: Session, dinosaur: Dinosaur) -> Fossil:
    row = Fossil(
        id=100001,
        dinosaur_id=dinosaur.id,
        identified_name="Tyrannosaurus rex",
        country_code="US",
        state="Montana",
        geological_formation="Hell Creek Formation",
        latitude=Decimal("46.879700"),
        longitude=Decimal("-110.362600"),
        collection_name="Hell Creek site 12",
        collection_no=50001,
        site_id=50001,
        collection_dates="1902",
        collection_type="taxonomic",
        occurrence_comments="tooth",
        stratcomments="Found in sandstone lens.",
        lithdescript="channel sandstone",
        composition="hydroxyapatite",
        architecture="compact or dense",
        fragmentation="unabraded",
        description="Famous Hell Creek tyrannosaur locality.",
        collectors="Barnum Brown",
        museum="AMNH",
        family="Tyrannosauridae",
        pres_mode="body",
        preservation_quality="good",
        abund_value=1,
        abund_unit="specimens",
        min_age_ma=Decimal("66.00"),
        max_age_ma=Decimal("68.00"),
        early_interval="Maastrichtian",
        main_image_url="https://mesozoica-production.up.railway.app/media/fossils/100001.webp",
    )
    session.add(row)
    session.commit()
    session.refresh(row)
    return row


def test_list_fossils_empty(client):
    response = client.get("/api/v1/fossils")
    assert response.status_code == 200
    body = response.json()
    assert body["items"] == []
    assert body["total"] == 0
    assert body["limit"] == 200
    assert body["offset"] == 0
    assert body["has_next"] is False


def test_list_fossils_returns_summary_fields(client, session):
    dinosaur = _seed_tyrannosaurus(session)
    site_type = _seed_site_type(session)
    _seed_hell_creek_site(session, site_type)
    fossil = _seed_hell_creek_fossil(session, dinosaur)

    response = client.get("/api/v1/fossils")
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 1
    assert len(body["items"]) == 1

    item = body["items"][0]
    assert item["id"] == fossil.id
    assert item["dinosaur_id"] == dinosaur.id
    assert item["identified_name"] == "Tyrannosaurus rex"
    assert item["country_code"] == "US"
    assert item["state"] == "Montana"
    assert item["geological_formation"] == "Hell Creek Formation"
    assert item["collection_name"] == "Hell Creek site 12"
    assert item["latitude"] == 46.8797
    assert item["longitude"] == -110.3626
    assert item["collection_dates"] == "1902"
    assert item["collection_type"] == "taxonomic"
    assert item["occurrence_comments"] == "tooth"
    assert item["stratcomments"] == "Found in sandstone lens."
    assert item["lithdescript"] == "channel sandstone"
    assert item["composition"] == "hydroxyapatite"
    assert item["architecture"] == "compact or dense"
    assert item["fragmentation"] == "unabraded"
    assert item["description"] == "Famous Hell Creek tyrannosaur locality."
    assert item["collectors"] == "Barnum Brown"
    assert item["museum"] == "AMNH"
    assert item["family"] == "Tyrannosauridae"
    assert item["pres_mode"] == "body"
    assert item["preservation_quality"] == "good"
    assert item["abund_value"] == 1
    assert item["abund_unit"] == "specimens"
    assert item["early_interval"] == "Maastrichtian"
    assert item["dinosaur_name"] == "Tyrannosaurus"
    assert item["dinosaur_main_image_url"].endswith("Tyrannosaurus.webp")
    assert item["main_image_url"].endswith("100001.webp")
    assert item["site_id"] == 50001
    assert item["site_main_image_url"].endswith("site-types/1.png")


def test_list_fossils_pagination(client, session):
    dinosaur = _seed_tyrannosaurus(session)
    for index, fossil_id in enumerate([100010, 100011, 100012]):
        session.add(
            Fossil(
                id=fossil_id,
                dinosaur_id=dinosaur.id,
                identified_name=f"Specimen {index}",
            )
        )
    session.commit()

    response = client.get("/api/v1/fossils?limit=2&offset=1&sort=name")
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 3
    assert body["limit"] == 2
    assert body["offset"] == 1
    assert len(body["items"]) == 2
    assert body["items"][0]["identified_name"] == "Specimen 1"


def test_list_fossils_random_requires_seed(client, session):
    dinosaur = _seed_tyrannosaurus(session)
    session.add(
        Fossil(id=100020, dinosaur_id=dinosaur.id, identified_name="Tyrannosaurus rex")
    )
    session.commit()

    response = client.get("/api/v1/fossils?sort=random")
    assert response.status_code == 400


def test_list_fossils_random_stable_order_with_seed(client, session):
    dinosaur = _seed_tyrannosaurus(session)
    for fossil_id, name in [
        (100030, "Alpha site"),
        (100031, "Beta site"),
        (100032, "Gamma site"),
    ]:
        session.add(
            Fossil(id=fossil_id, dinosaur_id=dinosaur.id, identified_name=name)
        )
    session.commit()

    seed = "fossil-seed-123"
    first = client.get(
        f"/api/v1/fossils?sort=random&seed={seed}&limit=1&offset=0"
    ).json()
    second = client.get(
        f"/api/v1/fossils?sort=random&seed={seed}&limit=1&offset=1"
    ).json()
    repeat = client.get(
        f"/api/v1/fossils?sort=random&seed={seed}&limit=1&offset=0"
    ).json()

    assert first["items"][0]["identified_name"] == repeat["items"][0]["identified_name"]
    assert first["items"][0]["identified_name"] != second["items"][0]["identified_name"]
    assert first["has_next"] is True


def test_list_fossils_random_spreads_duplicate_names(client, session):
    dinosaur = _seed_tyrannosaurus(session)
    for fossil_id in [100080, 100081, 100082, 100083]:
        session.add(
            Fossil(
                id=fossil_id,
                dinosaur_id=dinosaur.id,
                identified_name="Tyrannosaurus rex",
            )
        )
    session.commit()

    seed = "fossil-id-spread"
    random_ids = [
        item["id"]
        for item in client.get(
            f"/api/v1/fossils?sort=random&seed={seed}&limit=20"
        ).json()["items"]
    ]
    name_ids = [
        item["id"]
        for item in client.get("/api/v1/fossils?sort=name&limit=20").json()["items"]
    ]

    assert random_ids != name_ids


def _seed_timed_fossils(session: Session) -> None:
    cretaceous = Dinosaur(
        name="Tyrannosaurus",
        wikipedia_page_id=7001,
        wikipedia_title="Tyrannosaurus",
    )
    jurassic = Dinosaur(
        name="Stegosaurus",
        wikipedia_page_id=7002,
        wikipedia_title="Stegosaurus",
    )
    session.add_all([cretaceous, jurassic])
    session.commit()
    session.refresh(cretaceous)
    session.refresh(jurassic)

    session.add_all(
        [
            Fossil(
                id=100040,
                dinosaur_id=cretaceous.id,
                identified_name="Tyrannosaurus rex",
                min_age_ma=Decimal("66.00"),
                max_age_ma=Decimal("77.00"),
            ),
            Fossil(
                id=100041,
                dinosaur_id=jurassic.id,
                identified_name="Stegosaurus stenops",
                min_age_ma=Decimal("150.00"),
                max_age_ma=Decimal("155.00"),
            ),
            Fossil(
                id=100042,
                dinosaur_id=jurassic.id,
                identified_name="Undated stego",
            ),
        ]
    )
    session.commit()


def test_list_fossils_filter_by_search(client, session):
    _seed_timed_fossils(session)

    response = client.get("/api/v1/fossils?q=tyrannosaurus")
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 1
    assert body["items"][0]["identified_name"] == "Tyrannosaurus rex"


def test_list_fossils_filter_by_time_overlap(client, session):
    _seed_timed_fossils(session)

    response = client.get(
        "/api/v1/fossils?ma_younger=70&ma_older=80&sort=name"
    )
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 1
    assert body["items"][0]["identified_name"] == "Tyrannosaurus rex"


def test_list_fossils_filter_excludes_missing_dates_when_narrowed(client, session):
    _seed_timed_fossils(session)

    response = client.get(
        "/api/v1/fossils?ma_younger=66&ma_older=252&sort=name"
    )
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 3


def test_list_fossils_search_ignores_time_filter_for_undated_rows(client, session):
    dinosaur = Dinosaur(
        name="Brachiosaurus",
        wikipedia_page_id=8001,
        wikipedia_title="Brachiosaurus",
    )
    session.add(dinosaur)
    session.commit()
    session.refresh(dinosaur)
    session.add(
        Fossil(
            id=100050,
            dinosaur_id=dinosaur.id,
            identified_name="Brachiosaurus altithorax",
        )
    )
    session.commit()

    response = client.get(
        "/api/v1/fossils?q=brachiosaurus&ma_younger=150&ma_older=160&sort=name"
    )
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 1
    assert body["items"][0]["identified_name"] == "Brachiosaurus altithorax"


def test_list_fossils_filter_ma_requires_both_params(client):
    response = client.get("/api/v1/fossils?ma_younger=66")
    assert response.status_code == 400


def test_get_fossil_by_id(client, session):
    dinosaur = _seed_tyrannosaurus(session)
    site_type = _seed_site_type(session)
    _seed_hell_creek_site(session, site_type)
    fossil = _seed_hell_creek_fossil(session, dinosaur)

    response = client.get(f"/api/v1/fossils/{fossil.id}")
    assert response.status_code == 200
    body = response.json()
    assert body["id"] == fossil.id
    assert body["dinosaur_id"] == dinosaur.id
    assert body["identified_name"] == "Tyrannosaurus rex"
    assert body["geological_formation"] == "Hell Creek Formation"
    assert body["dinosaur_name"] == "Tyrannosaurus"
    assert body["dinosaur_main_image_url"].endswith("Tyrannosaurus.webp")
    assert body["site_id"] == 50001
    assert body["site_main_image_url"].endswith("site-types/1.png")


def test_get_fossil_not_found(client):
    response = client.get("/api/v1/fossils/99999")
    assert response.status_code == 404


def test_list_fossils_filter_by_dinosaur_id(client, session):
    tyrannosaurus = _seed_tyrannosaurus(session)
    hell_creek = _seed_hell_creek_fossil(session, tyrannosaurus)

    brachiosaurus = Dinosaur(
        name="Brachiosaurus",
        wikipedia_page_id=6001,
        wikipedia_title="Brachiosaurus",
    )
    session.add(brachiosaurus)
    session.commit()
    session.refresh(brachiosaurus)
    session.add(
        Fossil(
            id=100070,
            dinosaur_id=brachiosaurus.id,
            identified_name="Brachiosaurus altithorax",
        )
    )
    session.commit()

    response = client.get(
        f"/api/v1/fossils?dinosaur_id={tyrannosaurus.id}&sort=name"
    )
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 1
    assert body["items"][0]["id"] == hell_creek.id
    assert body["items"][0]["dinosaur_id"] == tyrannosaurus.id


def test_list_fossils_filter_by_unknown_dinosaur_id(client, session):
    _seed_tyrannosaurus(session)

    response = client.get("/api/v1/fossils?dinosaur_id=99999&sort=name")
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 0
    assert body["items"] == []


def test_list_fossils_filter_has_custom_image(client, session):
    curated_dino = _seed_tyrannosaurus(session)
    uncurated_dino = Dinosaur(
        name="Stegosaurus",
        wikipedia_page_id=6002,
        wikipedia_title="Stegosaurus",
        main_image_url="https://upload.wikimedia.org/wikipedia/commons/stego.jpg",
    )
    session.add(uncurated_dino)
    session.commit()
    session.refresh(uncurated_dino)

    session.add_all(
        [
            Fossil(
                id=100060,
                dinosaur_id=curated_dino.id,
                identified_name="Tyrannosaurus site A",
            ),
            Fossil(
                id=100061,
                dinosaur_id=curated_dino.id,
                identified_name="Tyrannosaurus site B",
            ),
            Fossil(
                id=100062,
                dinosaur_id=uncurated_dino.id,
                identified_name="Stegosaurus site",
            ),
        ]
    )
    session.commit()

    response = client.get("/api/v1/fossils?has_custom_image=true&sort=name")
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 2
    names = {item["identified_name"] for item in body["items"]}
    assert names == {"Tyrannosaurus site A", "Tyrannosaurus site B"}

    all_response = client.get("/api/v1/fossils?sort=name")
    assert all_response.status_code == 200
    assert all_response.json()["total"] == 3
