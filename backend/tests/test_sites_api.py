"""Tests for site read API."""

from decimal import Decimal

from sqlmodel import Session

from app.models.dinosaur import Dinosaur
from app.models.fossil import Fossil
from app.models.site import Site
from app.models.site_type import SiteType
from app.models.user_site import (
    USER_SITE_ROLE_DISCOVERER,
    USER_SITE_ROLE_PROTECTOR,
    UserSite,
)
from app.models.user import User
from app.core.security import create_access_token


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
        collection_no=50001,
        site_id=50001,
        main_image_url="https://mesozoica-production.up.railway.app/media/fossils/100001.webp",
    )
    session.add(row)
    session.commit()
    session.refresh(row)
    return row


def test_list_sites_empty(client):
    response = client.get("/api/v1/sites")
    assert response.status_code == 200
    body = response.json()
    assert body["items"] == []
    assert body["total"] == 0


def test_list_sites_random_requires_seed(client, session):
    _seed_site_type(session)
    response = client.get("/api/v1/sites?sort=random")
    assert response.status_code == 400


def test_list_sites_random_stable_order_with_seed(client, session):
    site_type = _seed_site_type(session)
    for site_id in (50001, 50002, 50003):
        session.add(
            Site(
                site_id=site_id,
                formation=f"Formation {site_id}",
                site_type_id=site_type.id,
            )
        )
    session.commit()

    seed = "stable-seed"
    first = client.get(
        f"/api/v1/sites?sort=random&seed={seed}&limit=1&offset=0"
    ).json()["items"][0]["site_id"]
    second = client.get(
        f"/api/v1/sites?sort=random&seed={seed}&limit=1&offset=1"
    ).json()["items"][0]["site_id"]
    first_again = client.get(
        f"/api/v1/sites?sort=random&seed={seed}&limit=1&offset=0"
    ).json()["items"][0]["site_id"]

    assert first == first_again
    assert first != second


def test_list_sites_random_shuffles_same_formation_sites(client, session):
    site_type = _seed_site_type(session)
    for site_id in (50011, 50012, 50013):
        session.add(
            Site(
                site_id=site_id,
                formation="Shared Formation",
                site_type_id=site_type.id,
            )
        )
    session.commit()

    seed = "shuffle-seed"
    ordered = [
        client.get(
            f"/api/v1/sites?sort=random&seed={seed}&limit=1&offset={offset}"
        ).json()["items"][0]["site_id"]
        for offset in range(3)
    ]

    assert ordered != [50011, 50012, 50013]
    assert sorted(ordered) == [50011, 50012, 50013]


def test_list_sites_returns_summary_fields(client, session):
    site_type = _seed_site_type(session)
    site = _seed_hell_creek_site(session, site_type)

    response = client.get("/api/v1/sites")
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 1
    item = body["items"][0]
    assert item["site_id"] == site.site_id
    assert item["formation"] == "Hell Creek Formation"
    assert item["country_code"] == "US"
    assert item["state"] == "Montana"
    assert item["rock_type"] == "sandstone"
    assert item["latitude"] == 46.8797
    assert item["longitude"] == -110.3626
    assert item["site_type_id"] == site_type.id
    assert item["site_type_period"] == "cretaceous"
    assert item["site_type_rock_type"] == "sandstone"
    assert item["main_image_url"].endswith("/media/site-types/1.png")
    assert item["status"] is None


def test_list_sites_has_custom_image_filter(client, session):
    site_type = _seed_site_type(session)
    _seed_hell_creek_site(session, site_type)
    session.add(
        Site(
            site_id=50002,
            formation="Unillustrated Formation",
            site_type_id=None,
        )
    )
    session.commit()

    response = client.get("/api/v1/sites", params={"has_custom_image": "true"})
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 1
    assert body["items"][0]["site_id"] == 50001


def test_get_site_by_id(client, session):
    site_type = _seed_site_type(session)
    site = _seed_hell_creek_site(session, site_type)

    response = client.get(f"/api/v1/sites/{site.site_id}")
    assert response.status_code == 200
    item = response.json()
    assert item["site_id"] == site.site_id
    assert item["formation"] == "Hell Creek Formation"


def test_get_site_not_found(client):
    response = client.get("/api/v1/sites/999999")
    assert response.status_code == 404


def test_get_site_without_rock_type_uses_period_fallback_image(client, session):
    site_type = _seed_site_type(session)
    session.add(
        Site(
            site_id=50003,
            latitude=Decimal("40.000000"),
            longitude=Decimal("-100.000000"),
            formation="Age-only Formation",
            min_age_ma=Decimal("72.00"),
            max_age_ma=Decimal("84.00"),
            rock_type=None,
            site_type_id=None,
        )
    )
    session.commit()

    response = client.get("/api/v1/sites/50003")
    assert response.status_code == 200
    item = response.json()
    assert item["rock_type"] is None
    assert item["site_type_id"] is None
    assert item["site_type_period"] == "cretaceous"
    assert item["site_type_rock_type"] == site_type.rock_type
    assert item["main_image_url"].endswith("/media/site-types/1.png")


def test_site_related_fossils_and_dinosaurs(client, session):
    site_type = _seed_site_type(session)
    site = _seed_hell_creek_site(session, site_type)
    dinosaur = _seed_tyrannosaurus(session)
    fossil = _seed_hell_creek_fossil(session, dinosaur)

    fossils_response = client.get(f"/api/v1/sites/{site.site_id}/fossils")
    assert fossils_response.status_code == 200
    fossils = fossils_response.json()["items"]
    assert len(fossils) == 1
    assert fossils[0]["id"] == fossil.id
    assert fossils[0]["main_image_url"].endswith("100001.webp")
    assert fossils[0]["identified_name"] == "Tyrannosaurus rex"

    dinos_response = client.get(f"/api/v1/sites/{site.site_id}/dinosaurs")
    assert dinos_response.status_code == 200
    dinos = dinos_response.json()["items"]
    assert len(dinos) == 1
    assert dinos[0]["id"] == dinosaur.id
    assert dinos[0]["name"] == "Tyrannosaurus"
    assert dinos[0]["main_image_url"].endswith("Tyrannosaurus.webp")

    groups_response = client.get(f"/api/v1/sites/{site.site_id}/groups")
    assert groups_response.status_code == 200
    groups = groups_response.json()["items"]
    assert len(groups) == 1
    assert groups[0]["dinosaur"]["id"] == dinosaur.id
    assert groups[0]["dinosaur"]["name"] == "Tyrannosaurus"
    assert len(groups[0]["fossils"]) == 1
    assert groups[0]["fossils"][0]["id"] == fossil.id


def test_list_sites_filters_by_data_source(client, session):
    site_type = _seed_site_type(session)
    _seed_hell_creek_site(session, site_type)
    session.add(
        Site(
            site_id=90001,
            formation="Field Prospect",
            data_source="field",
        )
    )
    session.commit()

    archive = client.get("/api/v1/sites", params={"data_source": "archive"})
    assert archive.status_code == 200
    assert archive.json()["total"] == 1
    assert archive.json()["items"][0]["site_id"] == 50001
    assert archive.json()["items"][0]["data_source"] == "archive"

    field = client.get(
        "/api/v1/sites",
        params={"data_source": "field", "show_all": True},
    )
    assert field.status_code == 200
    assert field.json()["total"] == 1
    assert field.json()["items"][0]["site_id"] == 90001
    assert field.json()["items"][0]["data_source"] == "field"


def test_list_field_sites_includes_status(client, session):
    site_type = _seed_site_type(session)
    session.add(
        Site(
            site_id=90002,
            latitude=Decimal("40.0"),
            longitude=Decimal("-100.0"),
            formation="Field Prospect",
            rock_type="sandstone",
            period="cretaceous",
            site_type_id=site_type.id,
            data_source="field",
        )
    )
    session.commit()

    response = client.get(
        "/api/v1/sites",
        params={"data_source": "field", "show_all": True},
    )
    assert response.status_code == 200
    item = response.json()["items"][0]
    assert item["site_id"] == 90002
    assert item["status"] == "hidden"

    archive = client.get("/api/v1/sites", params={"data_source": "archive"})
    assert archive.status_code == 200
    # No archive sites seeded in this test.
    assert archive.json()["total"] == 0


def test_list_field_sites_returns_latest_status(client, session):
    from datetime import datetime, timedelta, timezone

    site_type = _seed_site_type(session)
    session.add(
        Site(
            site_id=90003,
            latitude=Decimal("41.0"),
            longitude=Decimal("-101.0"),
            formation="Field Prospect",
            rock_type="sandstone",
            period="cretaceous",
            site_type_id=site_type.id,
            data_source="field",
        )
    )
    user = User(
        username="status_user",
        email="status@example.com",
        password="x",
    )
    session.add(user)
    session.commit()
    session.refresh(user)
    older = datetime.now(timezone.utc) - timedelta(days=2)
    newer = datetime.now(timezone.utc) - timedelta(hours=1)
    session.add(
        UserSite(
            user_id=user.id,
            site_id=90003,
            role=USER_SITE_ROLE_DISCOVERER,
            timestamp=older,
        )
    )
    session.add(
        UserSite(
            user_id=user.id,
            site_id=90003,
            role=USER_SITE_ROLE_PROTECTOR,
            timestamp=newer,
        )
    )
    session.commit()

    response = client.get(
        "/api/v1/sites",
        params={"data_source": "field", "show_all": True},
    )
    assert response.status_code == 200
    item = response.json()["items"][0]
    assert item["site_id"] == 90003
    assert item["status"] == "protected"


def test_list_field_sites_linked_only_by_default(client, session):
    site_type = _seed_site_type(session)
    session.add(
        Site(
            site_id=90004,
            latitude=Decimal("42.0"),
            longitude=Decimal("-102.0"),
            formation="Linked Prospect",
            rock_type="sandstone",
            period="cretaceous",
            site_type_id=site_type.id,
            data_source="field",
        )
    )
    session.add(
        Site(
            site_id=90005,
            latitude=Decimal("43.0"),
            longitude=Decimal("-103.0"),
            formation="Hidden Prospect",
            rock_type="sandstone",
            period="cretaceous",
            site_type_id=site_type.id,
            data_source="field",
        )
    )
    user = User(username="linker", email="linker@example.com", password="x")
    session.add(user)
    session.commit()
    session.refresh(user)
    session.add(
        UserSite(
            user_id=user.id,
            site_id=90004,
            role=USER_SITE_ROLE_DISCOVERER,
        )
    )
    session.commit()

    token = create_access_token({"sub": str(user.id)})
    linked = client.get(
        "/api/v1/sites",
        params={"data_source": "field"},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert linked.status_code == 200
    assert linked.json()["total"] == 1
    assert linked.json()["items"][0]["site_id"] == 90004

    anonymous = client.get("/api/v1/sites", params={"data_source": "field"})
    assert anonymous.status_code == 200
    assert anonymous.json()["total"] == 0


def test_discover_site_within_range(client, session):
    site_type = _seed_site_type(session)
    session.add(
        Site(
            site_id=90006,
            latitude=Decimal("40.000000"),
            longitude=Decimal("-100.000000"),
            formation="Discover Me",
            rock_type="sandstone",
            period="cretaceous",
            site_type_id=site_type.id,
            data_source="field",
        )
    )
    user = User(username="finder", email="finder@example.com", password="x")
    session.add(user)
    session.commit()
    session.refresh(user)
    token = create_access_token({"sub": str(user.id)})

    too_far = client.post(
        "/api/v1/sites/90006/discover",
        headers={"Authorization": f"Bearer {token}"},
        json={"lat": 40.01, "lon": -100.0},
    )
    assert too_far.status_code == 400

    ok = client.post(
        "/api/v1/sites/90006/discover",
        headers={"Authorization": f"Bearer {token}"},
        json={"lat": 40.001, "lon": -100.0},
    )
    assert ok.status_code == 200
    assert ok.json()["status"] == "discovered"

    linked = client.get(
        "/api/v1/sites",
        params={"data_source": "field"},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert linked.json()["total"] == 1
    assert linked.json()["items"][0]["site_id"] == 90006


def test_list_sites_rejects_invalid_data_source(client):
    response = client.get("/api/v1/sites", params={"data_source": "invalid"})
    assert response.status_code == 400
