"""Tests for site read API."""

from datetime import datetime
from decimal import Decimal

from sqlmodel import Session

from app.models.dinosaur_type import DinosaurType
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
from app.services.weather_service.service import WeatherSnapshot, cell_for
from app.services.weather_service.solar import period_at


def _stub_overcast_weather(monkeypatch) -> None:
    """Neutral weather/time so discovery_distance_m stays at YAML base (20 m)."""

    def _fake(*, lat: float, lon: float) -> WeatherSnapshot:
        return WeatherSnapshot(
            weather_type="overcast",
            temperature_c=15.0,
            weather_time=period_at(latitude=lat, longitude=lon),
            observed_at=datetime.now(),
            cell=cell_for(lat, lon),
            wmo_code=3,
        )

    monkeypatch.setattr("app.services.weather_service.get_weather", _fake)


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


def _admin_auth_headers(session: Session, *, username: str = "admin") -> dict[str, str]:
    user = User(
        username=username,
        email=f"{username}@example.com",
        password="x",
        is_admin=True,
    )
    session.add(user)
    session.commit()
    session.refresh(user)
    token = create_access_token({"sub": str(user.id)})
    return {"Authorization": f"Bearer {token}"}


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
        headers=_admin_auth_headers(session, username="field_list_admin"),
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
        headers=_admin_auth_headers(session, username="status_list_admin"),
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
        headers=_admin_auth_headers(session, username="latest_status_admin"),
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


def test_discover_site_within_range(client, session, monkeypatch):
    _stub_overcast_weather(monkeypatch)
    # Force chance roll to succeed (YAML discovery_chance is 0.1).
    monkeypatch.setattr(
        "app.services.site_service.discover.random.random",
        lambda: 0.0,
    )
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
        json={"lat": 40.001, "lon": -100.0},
    )
    assert too_far.status_code == 400

    ok = client.post(
        "/api/v1/sites/90006/discover",
        headers={"Authorization": f"Bearer {token}"},
        json={"lat": 40.0001, "lon": -100.0},
    )
    assert ok.status_code == 200
    assert ok.json()["site"]["status"] == "discovered"
    assert "fossils_ready" in ok.json()
    assert "surface_fossils" in ok.json()

    linked = client.get(
        "/api/v1/sites",
        params={"data_source": "field"},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert linked.json()["total"] == 1
    assert linked.json()["items"][0]["site_id"] == 90006

    notifications = client.get(
        "/api/v1/notifications",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert notifications.status_code == 200
    items = notifications.json()["notifications"]
    assert len(items) == 1
    assert items[0]["type"] == "site_discovered"
    assert items[0]["site_id"] == 90006
    assert "Discover Me" in items[0]["site_label"]

    # Second discover is idempotent — no duplicate notification.
    again = client.post(
        "/api/v1/sites/90006/discover",
        headers={"Authorization": f"Bearer {token}"},
        json={"lat": 40.0001, "lon": -100.0},
    )
    assert again.status_code == 200
    notifications2 = client.get(
        "/api/v1/notifications",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert len(notifications2.json()["notifications"]) == 1


def test_discover_site_chance_miss(client, session, monkeypatch):
    _stub_overcast_weather(monkeypatch)
    monkeypatch.setattr(
        "app.services.site_service.discover.random.random",
        lambda: 0.99,
    )
    site_type = _seed_site_type(session)
    session.add(
        Site(
            site_id=90016,
            latitude=Decimal("40.000000"),
            longitude=Decimal("-100.000000"),
            formation="Miss Me",
            rock_type="sandstone",
            period="cretaceous",
            site_type_id=site_type.id,
            data_source="field",
        )
    )
    user = User(username="misser", email="misser@example.com", password="x")
    session.add(user)
    session.commit()
    session.refresh(user)
    token = create_access_token({"sub": str(user.id)})

    miss = client.post(
        "/api/v1/sites/90016/discover",
        headers={"Authorization": f"Bearer {token}"},
        json={"lat": 40.0001, "lon": -100.0},
    )
    assert miss.status_code == 400
    body = miss.json()
    assert body["type"] == "DiscoveryChanceMissError"

    linked = client.get(
        "/api/v1/sites",
        params={"data_source": "field"},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert linked.json()["total"] == 0


def test_set_site_status_dropdown_flow(client, session):
    site_type = _seed_site_type(session)
    session.add(
        Site(
            site_id=90020,
            latitude=Decimal("40.000000"),
            longitude=Decimal("-100.000000"),
            formation="Status Site",
            rock_type="sandstone",
            period="cretaceous",
            site_type_id=site_type.id,
            data_source="field",
        )
    )
    user = User(
        username="statuser",
        email="statuser@example.com",
        password="x",
        is_admin=True,
    )
    session.add(user)
    session.commit()
    session.refresh(user)
    token = create_access_token({"sub": str(user.id)})
    headers = {"Authorization": f"Bearer {token}"}

    # Admin may set status without being within discovery range.
    discover = client.post(
        "/api/v1/sites/90020/status",
        headers=headers,
        json={"status": "discovered", "lat": 41.0, "lon": -100.0},
    )
    assert discover.status_code == 200
    body = discover.json()
    site_status = body["site"]["status"] if "site" in body else body["status"]
    assert site_status == "discovered"
    notifs = client.get("/api/v1/notifications", headers=headers)
    assert len(notifs.json()["notifications"]) == 1
    assert notifs.json()["notifications"][0]["type"] == "site_discovered"

    excavate = client.post(
        "/api/v1/sites/90020/status",
        headers=headers,
        json={"status": "excavation"},
    )
    assert excavate.status_code == 200
    assert excavate.json()["status"] == "excavation"

    protect = client.post(
        "/api/v1/sites/90020/status",
        headers=headers,
        json={"status": "protected"},
    )
    assert protect.status_code == 200
    assert protect.json()["status"] == "protected"

    exhaust = client.post(
        "/api/v1/sites/90020/status",
        headers=headers,
        json={"status": "exhausted"},
    )
    assert exhaust.status_code == 200
    assert exhaust.json()["status"] == "exhausted"

    hidden = client.post(
        "/api/v1/sites/90020/status",
        headers=headers,
        json={"status": "hidden"},
    )
    assert hidden.status_code == 200
    assert hidden.json()["status"] == "hidden"

    # Re-discover from hidden creates another discovery notification.
    rediscover = client.post(
        "/api/v1/sites/90020/status",
        headers=headers,
        json={"status": "discovered"},
    )
    assert rediscover.status_code == 200
    rediscover_body = rediscover.json()
    rediscover_status = (
        rediscover_body["site"]["status"]
        if "site" in rediscover_body
        else rediscover_body["status"]
    )
    assert rediscover_status == "discovered"
    notifs2 = client.get("/api/v1/notifications", headers=headers)
    assert len(notifs2.json()["notifications"]) == 2
    assert all(
        n["type"] == "site_discovered" for n in notifs2.json()["notifications"]
    )


def test_set_site_status_allowed_for_non_admin_within_range(client, session):
    site_type = _seed_site_type(session)
    session.add(
        Site(
            site_id=90021,
            latitude=Decimal("40.000000"),
            longitude=Decimal("-100.000000"),
            formation="Non Admin Site",
            rock_type="sandstone",
            period="cretaceous",
            site_type_id=site_type.id,
            data_source="field",
        )
    )
    user = User(username="pleb", email="pleb@example.com", password="x")
    session.add(user)
    session.commit()
    session.refresh(user)
    token = create_access_token({"sub": str(user.id)})

    too_far = client.post(
        "/api/v1/sites/90021/status",
        headers={"Authorization": f"Bearer {token}"},
        json={"status": "protected", "lat": 41.0, "lon": -100.0},
    )
    assert too_far.status_code == 400

    response = client.post(
        "/api/v1/sites/90021/status",
        headers={"Authorization": f"Bearer {token}"},
        json={"status": "protected", "lat": 40.0001, "lon": -100.0},
    )
    assert response.status_code == 200
    assert response.json()["status"] == "protected"


def test_show_all_ignored_for_non_admin(client, session):
    site_type = _seed_site_type(session)
    session.add(
        Site(
            site_id=90022,
            latitude=Decimal("44.0"),
            longitude=Decimal("-104.0"),
            formation="Secret Prospect",
            rock_type="sandstone",
            period="cretaceous",
            site_type_id=site_type.id,
            data_source="field",
        )
    )
    user = User(username="viewer", email="viewer@example.com", password="x")
    session.add(user)
    session.commit()
    session.refresh(user)
    token = create_access_token({"sub": str(user.id)})

    response = client.get(
        "/api/v1/sites",
        params={"data_source": "field", "show_all": True},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.status_code == 200
    assert response.json()["total"] == 0


def test_nearby_discoverable_excludes_linked_and_non_discoverable(client, session):
    site_type = _seed_site_type(session)
    session.add(
        Site(
            site_id=90010,
            latitude=Decimal("40.000000"),
            longitude=Decimal("-100.000000"),
            formation="Hidden Nearby",
            rock_type="sandstone",
            period="cretaceous",
            site_type_id=site_type.id,
            data_source="field",
        )
    )
    session.add(
        Site(
            site_id=90011,
            latitude=Decimal("40.000500"),
            longitude=Decimal("-100.000000"),
            formation="Already Linked",
            rock_type="sandstone",
            period="cretaceous",
            site_type_id=site_type.id,
            data_source="field",
        )
    )
    session.add(
        Site(
            site_id=90012,
            latitude=Decimal("40.000800"),
            longitude=Decimal("-100.000000"),
            formation="Protected Nearby",
            rock_type="sandstone",
            period="cretaceous",
            site_type_id=site_type.id,
            data_source="field",
        )
    )
    user = User(username="prox", email="prox@example.com", password="x")
    other = User(username="other", email="other@example.com", password="x")
    session.add(user)
    session.add(other)
    session.commit()
    session.refresh(user)
    session.refresh(other)
    session.add(
        UserSite(
            user_id=user.id,
            site_id=90011,
            role=USER_SITE_ROLE_DISCOVERER,
        )
    )
    session.add(
        UserSite(
            user_id=other.id,
            site_id=90012,
            role=USER_SITE_ROLE_PROTECTOR,
        )
    )
    session.commit()
    token = create_access_token({"sub": str(user.id)})

    response = client.get(
        "/api/v1/sites/nearby-discoverable",
        params={"lat": 40.0, "lon": -100.0, "radius_km": 1.0},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.status_code == 200
    items = response.json()["items"]
    ids = {item["site_id"] for item in items}
    assert 90010 in ids
    assert 90011 not in ids
    assert 90012 not in ids


def test_register_device_token(client, session):
    user = User(username="pusher", email="pusher@example.com", password="x")
    session.add(user)
    session.commit()
    session.refresh(user)
    token = create_access_token({"sub": str(user.id)})

    response = client.post(
        "/api/v1/auth/device-token",
        headers={"Authorization": f"Bearer {token}"},
        json={"token": "fcm-token-abc", "platform": "ios"},
    )
    assert response.status_code == 204

    # Upsert same token for same user.
    again = client.post(
        "/api/v1/auth/device-token",
        headers={"Authorization": f"Bearer {token}"},
        json={"token": "fcm-token-abc", "platform": "android"},
    )
    assert again.status_code == 204


def test_list_sites_rejects_invalid_data_source(client):
    response = client.get("/api/v1/sites", params={"data_source": "invalid"})
    assert response.status_code == 400


def test_list_sites_filters_by_bbox(client, session):
    from app.models.data_source import DATA_SOURCE_FIELD

    site_type = _seed_site_type(session)
    session.add(
        Site(
            site_id=62001,
            latitude=Decimal("40.0"),
            longitude=Decimal("-100.0"),
            formation="Inside",
            site_type_id=site_type.id,
            data_source=DATA_SOURCE_FIELD,
        )
    )
    session.add(
        Site(
            site_id=62002,
            latitude=Decimal("50.0"),
            longitude=Decimal("-100.0"),
            formation="Outside",
            site_type_id=site_type.id,
            data_source=DATA_SOURCE_FIELD,
        )
    )
    session.commit()

    headers = _admin_auth_headers(session, username="bbox_admin")
    response = client.get(
        "/api/v1/sites",
        params={
            "data_source": "field",
            "show_all": "true",
            "min_lat": 39.0,
            "max_lat": 41.0,
            "min_lon": -101.0,
            "max_lon": -99.0,
        },
        headers=headers,
    )
    assert response.status_code == 200
    ids = [item["site_id"] for item in response.json()["items"]]
    assert ids == [62001]
    assert response.json()["total"] == 1


def test_list_sites_bbox_requires_all_params(client, session):
    response = client.get(
        "/api/v1/sites",
        params={"min_lat": 39.0, "max_lat": 41.0, "min_lon": -101.0},
    )
    assert response.status_code == 400


def test_list_sites_filters_by_how_discovered(client, session):
    from app.models.data_source import DATA_SOURCE_FIELD
    from app.models.site import HOW_DISCOVERED_WALK, HOW_DISCOVERED_AERIAL_RECON

    site_type = _seed_site_type(session)
    session.add(
        Site(
            site_id=60001,
            latitude=Decimal("40.0"),
            longitude=Decimal("-100.0"),
            formation="Walk Site",
            site_type_id=site_type.id,
            data_source=DATA_SOURCE_FIELD,
            how_discovered=HOW_DISCOVERED_WALK,
        )
    )
    session.add(
        Site(
            site_id=60002,
            latitude=Decimal("40.1"),
            longitude=Decimal("-100.1"),
            formation="Recon Site",
            site_type_id=site_type.id,
            data_source=DATA_SOURCE_FIELD,
            how_discovered=HOW_DISCOVERED_AERIAL_RECON,
        )
    )
    session.commit()

    headers = _admin_auth_headers(session, username="how_admin")
    response = client.get(
        "/api/v1/sites",
        params={
            "data_source": "field",
            "show_all": "true",
            "how_discovered": ["walk"],
        },
        headers=headers,
    )
    assert response.status_code == 200
    ids = [item["site_id"] for item in response.json()["items"]]
    assert ids == [60001]


def test_list_sites_sort_by_distance(client, session):
    from app.models.data_source import DATA_SOURCE_FIELD

    site_type = _seed_site_type(session)
    # Origin at 40,-100; nearer site first.
    session.add(
        Site(
            site_id=61001,
            latitude=Decimal("41.0"),
            longitude=Decimal("-100.0"),
            formation="Far",
            site_type_id=site_type.id,
            data_source=DATA_SOURCE_FIELD,
        )
    )
    session.add(
        Site(
            site_id=61002,
            latitude=Decimal("40.01"),
            longitude=Decimal("-100.0"),
            formation="Near",
            site_type_id=site_type.id,
            data_source=DATA_SOURCE_FIELD,
        )
    )
    session.commit()

    headers = _admin_auth_headers(session, username="dist_admin")
    response = client.get(
        "/api/v1/sites",
        params={
            "data_source": "field",
            "show_all": "true",
            "sort": "distance",
            "lat": 40.0,
            "lon": -100.0,
            "limit": 10,
        },
        headers=headers,
    )
    assert response.status_code == 200
    ids = [item["site_id"] for item in response.json()["items"]]
    assert ids[:2] == [61002, 61001]
    assert response.json()["has_next"] is False


def test_list_sites_sort_distance_requires_lat_lon(client, session):
    response = client.get("/api/v1/sites", params={"sort": "distance"})
    assert response.status_code == 400


def test_list_sites_discovery_time_filter_and_sort(client, session):
    from datetime import datetime, timedelta

    from app.models.data_source import DATA_SOURCE_FIELD
    from app.models.site import HOW_DISCOVERED_WALK

    site_type = _seed_site_type(session)
    user = User(username="discoverer", email="d@example.com", password="x")
    session.add(user)
    session.commit()
    session.refresh(user)

    now = datetime.utcnow()
    older = now - timedelta(days=30)
    newer = now - timedelta(days=2)

    for site_id, ts in ((62001, older), (62002, newer)):
        session.add(
            Site(
                site_id=site_id,
                latitude=Decimal("40.0"),
                longitude=Decimal("-100.0"),
                formation=f"Site {site_id}",
                site_type_id=site_type.id,
                data_source=DATA_SOURCE_FIELD,
                how_discovered=HOW_DISCOVERED_WALK,
            )
        )
        session.add(
            UserSite(
                user_id=int(user.id),
                site_id=site_id,
                role=USER_SITE_ROLE_DISCOVERER,
                timestamp=ts,
            )
        )
    session.commit()

    token = create_access_token({"sub": str(user.id)})
    headers = {"Authorization": f"Bearer {token}"}

    # Newest first
    newest = client.get(
        "/api/v1/sites",
        params={
            "data_source": "field",
            "sort": "discovered_at_desc",
            "limit": 10,
        },
        headers=headers,
    )
    assert newest.status_code == 200
    assert [i["site_id"] for i in newest.json()["items"][:2]] == [62002, 62001]

    # Oldest first
    oldest = client.get(
        "/api/v1/sites",
        params={
            "data_source": "field",
            "sort": "discovered_at",
            "limit": 10,
        },
        headers=headers,
    )
    assert oldest.status_code == 200
    assert [i["site_id"] for i in oldest.json()["items"][:2]] == [62001, 62002]

    # Time window: only newer
    window = client.get(
        "/api/v1/sites",
        params={
            "data_source": "field",
            "discovered_after": (now - timedelta(days=7)).isoformat(),
            "discovered_before": now.isoformat(),
            "limit": 10,
        },
        headers=headers,
    )
    assert window.status_code == 200
    assert [i["site_id"] for i in window.json()["items"]] == [62002]


def test_list_sites_discovery_sort_requires_auth(client, session):
    response = client.get("/api/v1/sites", params={"sort": "discovered_at"})
    assert response.status_code == 400
