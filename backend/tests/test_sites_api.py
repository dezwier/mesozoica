"""Tests for site read API."""

from decimal import Decimal

from sqlmodel import Session

from app.models.dinosaur import Dinosaur
from app.models.fossil import Fossil
from app.models.fossil_clean import FossilClean
from app.models.site_clean import SiteClean
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


def _seed_hell_creek_site(session: Session, site_type: SiteType) -> SiteClean:
    row = SiteClean(
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
        main_image_url="https://mesozoica-production.up.railway.app/media/fossils/100001.webp",
    )
    session.add(row)
    session.commit()
    session.refresh(row)
    return row


def _seed_fossil_clean(
    session: Session,
    *,
    fossil: Fossil,
    site: SiteClean,
    dinosaur: Dinosaur,
) -> FossilClean:
    row = FossilClean(
        fossil_id=fossil.id,
        site_id=site.site_id,
        dinosaur_id=dinosaur.id,
        name="Tyrannosaurus rex",
        type="body",
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


def test_list_sites_has_custom_image_filter(client, session):
    site_type = _seed_site_type(session)
    _seed_hell_creek_site(session, site_type)
    session.add(
        SiteClean(
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
        SiteClean(
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
    _seed_fossil_clean(session, fossil=fossil, site=site, dinosaur=dinosaur)

    fossils_response = client.get(f"/api/v1/sites/{site.site_id}/fossils")
    assert fossils_response.status_code == 200
    fossils = fossils_response.json()["items"]
    assert len(fossils) == 1
    assert fossils[0]["id"] == fossil.id
    assert fossils[0]["main_image_url"].endswith("100001.webp")

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
