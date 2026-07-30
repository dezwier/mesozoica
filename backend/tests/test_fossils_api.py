"""Tests for fossil read API."""

from decimal import Decimal

from sqlmodel import Session

from app.core.security import create_access_token
from app.models.dinosaur_type import DinosaurType
from app.models.fossil import Fossil
from app.models.site import Site
from app.models.site_type import SiteType
from app.models.user import User
from app.models.user_fossil import USER_FOSSIL_ROLE_IN_SITU, UserFossil


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


def _seed_tyrannosaurus(session: Session) -> DinosaurType:
    row = DinosaurType(
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


def _seed_hell_creek_fossil(session: Session, dinosaur: DinosaurType) -> Fossil:
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
    cretaceous = DinosaurType(
        name="Tyrannosaurus",
        wikipedia_page_id=7001,
        wikipedia_title="Tyrannosaurus",
    )
    jurassic = DinosaurType(
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


def test_list_fossils_filter_by_dino_q(client, session):
    _seed_timed_fossils(session)

    response = client.get("/api/v1/fossils?dino_q=tyrannosaurus&sort=name")
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 1
    assert body["items"][0]["identified_name"] == "Tyrannosaurus rex"


def test_list_fossils_filter_by_fossil_q(client, session):
    _seed_timed_fossils(session)

    response = client.get("/api/v1/fossils?fossil_q=stenops&sort=name")
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 1
    assert body["items"][0]["identified_name"] == "Stegosaurus stenops"


def test_list_fossils_filter_by_llm_enriched(client, session):
    dinosaur = _seed_tyrannosaurus(session)
    session.add_all(
        [
            Fossil(
                id=100090,
                dinosaur_id=dinosaur.id,
                identified_name="Enriched specimen",
                llm_enriched=True,
            ),
            Fossil(
                id=100091,
                dinosaur_id=dinosaur.id,
                identified_name="Pending specimen",
                llm_enriched=False,
            ),
        ]
    )
    session.commit()

    response = client.get("/api/v1/fossils?llm_enriched=true&sort=name")
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 1
    assert body["items"][0]["identified_name"] == "Enriched specimen"


def test_list_fossils_filter_by_custom_fossil_image(client, session):
    dinosaur = _seed_tyrannosaurus(session)
    session.add_all(
        [
            Fossil(
                id=100100,
                dinosaur_id=dinosaur.id,
                identified_name="Curated fossil image",
                main_image_url="https://mesozoica-production.up.railway.app/media/fossils/100100.webp",
            ),
            Fossil(
                id=100101,
                dinosaur_id=dinosaur.id,
                identified_name="No fossil image",
            ),
        ]
    )
    session.commit()

    response = client.get("/api/v1/fossils?has_custom_fossil_image=true&sort=name")
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 1
    assert body["items"][0]["identified_name"] == "Curated fossil image"


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
    dinosaur = DinosaurType(
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

    brachiosaurus = DinosaurType(
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
    uncurated_dino = DinosaurType(
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


def test_list_fossils_filters_by_data_source(client, session):
    dinosaur = _seed_tyrannosaurus(session)
    site_type = _seed_site_type(session)
    _seed_hell_creek_site(session, site_type)
    _seed_hell_creek_fossil(session, dinosaur)
    session.add(
        Fossil(
            id=200001,
            dinosaur_id=dinosaur.id,
            identified_name="Field specimen",
            data_source="field",
            depth_cm=100,
        )
    )
    session.commit()

    archive = client.get("/api/v1/fossils", params={"data_source": "archive"})
    assert archive.status_code == 200
    assert archive.json()["total"] == 1
    assert archive.json()["items"][0]["id"] == 100001
    assert archive.json()["items"][0]["data_source"] == "archive"

    # Anonymous / non-admin viewers only see field fossils they discovered.
    field = client.get("/api/v1/fossils", params={"data_source": "field"})
    assert field.status_code == 200
    assert field.json()["total"] == 0

    admin = User(
        username="fossil_admin",
        email="fossil_admin@example.com",
        password="x",
        is_admin=True,
    )
    session.add(admin)
    session.commit()
    session.refresh(admin)
    token = create_access_token({"sub": str(admin.id)})
    admin_field = client.get(
        "/api/v1/fossils",
        params={"data_source": "field"},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert admin_field.status_code == 200
    # Admins also only see linked fossils in the catalog.
    assert admin_field.json()["total"] == 0

    admin_peek = client.get(
        "/api/v1/fossils",
        params={"data_source": "field", "include_hidden": "true"},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert admin_peek.status_code == 200
    assert admin_peek.json()["total"] == 1
    assert admin_peek.json()["items"][0]["id"] == 200001
    assert admin_peek.json()["items"][0]["data_source"] == "field"
    assert admin_peek.json()["items"][0]["status"] == "hidden"
    assert admin_peek.json()["items"][0]["depth_cm"] == 100


def test_list_field_fossils_includes_in_situ_links(client, session):
    dinosaur = _seed_tyrannosaurus(session)
    site_type = _seed_site_type(session)
    _seed_hell_creek_site(session, site_type)
    session.add(
        Fossil(
            id=200002,
            dinosaur_id=dinosaur.id,
            identified_name="Discovered field specimen",
            data_source="field",
            depth_cm=0,
            llm_enriched=False,
        )
    )
    user = User(
        username="fossil_finder",
        email="fossil_finder@example.com",
        password="x",
    )
    session.add(user)
    session.commit()
    session.refresh(user)
    session.add(
        UserFossil(
            user_id=user.id,
            fossil_id=200002,
            role=USER_FOSSIL_ROLE_IN_SITU,
        )
    )
    session.commit()
    token = create_access_token({"sub": str(user.id)})

    # Default catalog filter llm_enriched=true must not hide field finds.
    response = client.get(
        "/api/v1/fossils",
        params={"data_source": "field", "llm_enriched": "true", "sort": "name"},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.status_code == 200
    # Field fossils historically omit llm_enriched; catalog should still
    # return discovers when the client omits that filter. With the filter
    # on, unenriched fossils stay hidden — so unfiltered field list is the
    # contract for the app field catalog.
    unfiltered = client.get(
        "/api/v1/fossils",
        params={"data_source": "field", "sort": "name"},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert unfiltered.status_code == 200
    assert unfiltered.json()["total"] == 1
    assert unfiltered.json()["items"][0]["id"] == 200002
    assert unfiltered.json()["items"][0]["status"] == "in_situ"

    enriched_only = response.json()
    assert enriched_only["total"] == 0


def test_list_fossils_rejects_invalid_data_source(client):
    response = client.get("/api/v1/fossils", params={"data_source": "invalid"})
    assert response.status_code == 400


def test_set_fossil_status_admin_flow(client, session):
    dinosaur = _seed_tyrannosaurus(session)
    site_type = _seed_site_type(session)
    _seed_hell_creek_site(session, site_type)
    session.add(
        Fossil(
            id=200010,
            dinosaur_id=dinosaur.id,
            identified_name="Status specimen",
            data_source="field",
            depth_cm=50,
            llm_enriched=False,
            site_id=50001,
        )
    )
    admin = User(
        username="fossil_status_admin",
        email="fossil_status_admin@example.com",
        password="x",
        is_admin=True,
    )
    non_admin = User(
        username="fossil_status_user",
        email="fossil_status_user@example.com",
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
        "/api/v1/fossils/200010/status",
        headers=user_headers,
        json={"status": "located"},
    )
    assert forbidden.status_code == 403

    located = client.post(
        "/api/v1/fossils/200010/status",
        headers=admin_headers,
        json={"status": "located"},
    )
    assert located.status_code == 200
    assert located.json()["status"] == "located"

    inventory = client.get(
        "/api/v1/fossils",
        params={"data_source": "field", "sort": "name"},
        headers=admin_headers,
    )
    assert inventory.status_code == 200
    assert inventory.json()["total"] == 1
    assert inventory.json()["items"][0]["id"] == 200010
    assert inventory.json()["items"][0]["status"] == "located"

    excavated = client.post(
        "/api/v1/fossils/200010/status",
        headers=admin_headers,
        json={"status": "excavated"},
    )
    assert excavated.status_code == 200
    assert excavated.json()["status"] == "excavated"

    hidden = client.post(
        "/api/v1/fossils/200010/status",
        headers=admin_headers,
        json={"status": "hidden"},
    )
    assert hidden.status_code == 200
    assert hidden.json()["status"] == "hidden"

    after_hidden = client.get(
        "/api/v1/fossils",
        params={"data_source": "field", "sort": "name"},
        headers=admin_headers,
    )
    assert after_hidden.json()["total"] == 0

    session.add(
        Fossil(
            id=100010,
            dinosaur_id=dinosaur.id,
            identified_name="Archive specimen",
            data_source="archive",
            llm_enriched=False,
        )
    )
    session.commit()
    archive = client.post(
        "/api/v1/fossils/100010/status",
        headers=admin_headers,
        json={"status": "located"},
    )
    # Archive fossils are not status-editable (field only).
    assert archive.status_code == 404
