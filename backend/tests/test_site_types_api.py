"""Tests for public site-type catalog API."""

from decimal import Decimal

from sqlmodel import Session

from app.core.security import create_access_token
from app.models.site import Site
from app.models.site_type import SiteType
from app.models.user import User
from app.models.user_site import USER_SITE_ROLE_DISCOVERER, UserSite


def _seed_site_type(
    session: Session,
    *,
    period: str = "cretaceous",
    rock_type: str = "sandstone",
    main_image_url: str | None = "https://example.com/media/site-types/1.png",
) -> SiteType:
    row = SiteType(
        period=period,
        rock_type=rock_type,
        main_image_url=main_image_url,
    )
    session.add(row)
    session.commit()
    session.refresh(row)
    return row


def _seed_site(
    session: Session,
    site_type: SiteType,
    *,
    site_id: int = 50001,
    version: str = "Original",
) -> Site:
    row = Site(
        site_id=site_id,
        latitude=Decimal("46.879700"),
        longitude=Decimal("-110.362600"),
        country_code="US",
        state="Montana",
        rock_type=site_type.rock_type,
        formation="Hell Creek Formation",
        min_age_ma=Decimal("66.00"),
        max_age_ma=Decimal("68.00"),
        site_type_id=site_type.id,
        version=version,
    )
    session.add(row)
    session.commit()
    session.refresh(row)
    return row


def _user(session: Session, *, username: str = "player") -> User:
    user = User(
        username=username,
        email=f"{username}@example.com",
        password="x",
        is_admin=False,
    )
    session.add(user)
    session.commit()
    session.refresh(user)
    return user


def _auth_headers(user: User) -> dict[str, str]:
    token = create_access_token({"sub": str(user.id)})
    return {"Authorization": f"Bearer {token}"}


def _link_site(session: Session, *, user_id: int, site_id: int) -> None:
    session.add(
        UserSite(
            user_id=user_id,
            site_id=site_id,
            role=USER_SITE_ROLE_DISCOVERER,
        )
    )
    session.commit()


def test_list_site_types_empty(client):
    response = client.get("/api/v1/site-types")
    assert response.status_code == 200
    body = response.json()
    assert body["items"] == []
    assert body["total"] == 0
    assert body["has_next"] is False


def test_list_site_types_ordered_and_anonymous_has_no_owned(client, session):
    _seed_site_type(session, period="jurassic", rock_type="mudstone")
    owned_type = _seed_site_type(session, period="cretaceous", rock_type="sandstone")
    _seed_site_type(session, period="triassic", rock_type="shale")
    site = _seed_site(session, owned_type)
    user = _user(session)
    _link_site(session, user_id=int(user.id), site_id=int(site.site_id))

    response = client.get("/api/v1/site-types")
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 3
    periods = [item["period"] for item in body["items"]]
    # Geological order: triassic → jurassic → cretaceous
    assert periods == ["triassic", "jurassic", "cretaceous"]
    assert all(item["owned_occurrences"] == [] for item in body["items"])


def test_list_site_types_owned_occurrences_for_viewer(client, session):
    owned_type = _seed_site_type(session, period="cretaceous", rock_type="sandstone")
    other_type = _seed_site_type(session, period="triassic", rock_type="shale")
    site_a = _seed_site(session, owned_type, site_id=50001, version="Original")
    site_b = _seed_site(session, owned_type, site_id=50002, version="v1")
    _seed_site(session, other_type, site_id=50003)
    user = _user(session)
    _link_site(session, user_id=int(user.id), site_id=int(site_a.site_id))
    _link_site(session, user_id=int(user.id), site_id=int(site_b.site_id))

    response = client.get(
        "/api/v1/site-types",
        headers=_auth_headers(user),
    )
    assert response.status_code == 200
    body = response.json()
    by_id = {item["id"]: item for item in body["items"]}

    owned = by_id[int(owned_type.id)]
    assert owned["period"] == "cretaceous"
    assert owned["rock_type"] == "sandstone"
    assert owned["main_image_url"] is not None
    owned_ids = [thumb["id"] for thumb in owned["owned_occurrences"]]
    assert owned_ids == [50001, 50002]
    assert owned["owned_occurrences"][0]["version"] == "Original"
    assert owned["owned_occurrences"][1]["version"] == "v1"

    other = by_id[int(other_type.id)]
    assert other["owned_occurrences"] == []


def test_list_site_types_pagination(client, session):
    _seed_site_type(session, period="cretaceous", rock_type="sandstone")
    _seed_site_type(session, period="jurassic", rock_type="mudstone")
    _seed_site_type(session, period="triassic", rock_type="shale")

    response = client.get("/api/v1/site-types", params={"limit": 2, "offset": 0})
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 3
    assert len(body["items"]) == 2
    assert body["has_next"] is True

    response = client.get("/api/v1/site-types", params={"limit": 2, "offset": 2})
    assert response.status_code == 200
    body = response.json()
    assert len(body["items"]) == 1
    assert body["has_next"] is False


def test_list_site_types_dedupes_multiple_user_site_roles(client, session):
    site_type = _seed_site_type(session)
    site = _seed_site(session, site_type)
    user = _user(session)
    _link_site(session, user_id=int(user.id), site_id=int(site.site_id))
    session.add(
        UserSite(
            user_id=int(user.id),
            site_id=int(site.site_id),
            role="surveyor",
        )
    )
    session.commit()

    response = client.get(
        "/api/v1/site-types",
        headers=_auth_headers(user),
    )
    assert response.status_code == 200
    item = response.json()["items"][0]
    assert len(item["owned_occurrences"]) == 1
    assert item["owned_occurrences"][0]["id"] == int(site.site_id)
