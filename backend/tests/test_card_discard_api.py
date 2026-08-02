"""Caller-scoped discard endpoints for inventory cards."""

from decimal import Decimal

from sqlmodel import Session, col, select

from app.core.security import create_access_token
from app.models.data_source import DATA_SOURCE_FIELD
from app.models.dinosaur import Dinosaur
from app.models.fossil import Fossil
from app.models.site import Site
from app.models.site_type import SiteType
from app.models.tool import Tool
from app.models.tool_session import (
    ACTION_KEY_ORBIT_SURVEY,
    SESSION_STATUS_ACTIVE,
    SESSION_STATUS_CANCELLED,
    ToolSession,
)
from app.models.tool_type import ToolType
from app.models.user import User
from app.models.user_dinosaur import USER_DINOSAUR_ROLE_MODELLED, UserDinosaur
from app.models.user_fossil import USER_FOSSIL_ROLE_IN_SITU, UserFossil
from app.models.user_site import USER_SITE_ROLE_DISCOVERER, UserSite
from app.models.user_tool import USER_TOOL_ACTION_OWNED, UserTool
from tests.helpers.dinosaur_fixtures import seed_dinosaur_type


def _auth_headers(user: User) -> dict[str, str]:
    return {"Authorization": f"Bearer {create_access_token({'sub': str(user.id)})}"}


def _user(
    session: Session,
    *,
    username: str,
    is_admin: bool = False,
) -> User:
    user = User(
        username=username,
        email=f"{username}@example.com",
        password="x",
        is_admin=is_admin,
    )
    session.add(user)
    session.commit()
    session.refresh(user)
    return user


def _seed_site_type(session: Session) -> SiteType:
    row = SiteType(
        period="cretaceous",
        rock_type="sandstone",
        main_image_url="https://example.com/site-types/1.png",
    )
    session.add(row)
    session.commit()
    session.refresh(row)
    return row


def test_discard_dinosaur_removes_from_inventory_and_keeps_other_user(
    client, session
):
    dino_type = seed_dinosaur_type(
        session, name="Discardosaurus", wikipedia_page_id=900001
    )
    owner = _user(session, username="dino_owner")
    other = _user(session, username="dino_other")
    occurrence = Dinosaur(dinosaur_type_id=int(dino_type.id), version="Original")
    session.add(occurrence)
    session.flush()
    session.add(
        UserDinosaur(
            user_id=int(owner.id),
            dinosaur_id=int(occurrence.id),
            role=USER_DINOSAUR_ROLE_MODELLED,
        )
    )
    session.add(
        UserDinosaur(
            user_id=int(other.id),
            dinosaur_id=int(occurrence.id),
            role=USER_DINOSAUR_ROLE_MODELLED,
        )
    )
    session.commit()
    occurrence_id = int(occurrence.id)

    unauth = client.post(f"/api/v1/dinosaurs/{occurrence_id}/discard")
    assert unauth.status_code in (401, 403)

    discarded = client.post(
        f"/api/v1/dinosaurs/{occurrence_id}/discard",
        headers=_auth_headers(owner),
    )
    assert discarded.status_code == 204

    owner_inventory = client.get(
        "/api/v1/dinosaurs",
        params={"mode": "inventory", "sort": "name"},
        headers=_auth_headers(owner),
    )
    assert owner_inventory.status_code == 200
    assert owner_inventory.json()["total"] == 0

    other_inventory = client.get(
        "/api/v1/dinosaurs",
        params={"mode": "inventory", "sort": "name"},
        headers=_auth_headers(other),
    )
    assert other_inventory.status_code == 200
    assert other_inventory.json()["total"] == 1
    assert other_inventory.json()["items"][0]["id"] == occurrence_id

    remaining = session.exec(
        select(UserDinosaur).where(col(UserDinosaur.dinosaur_id) == occurrence_id)
    ).all()
    assert len(remaining) == 1
    assert remaining[0].user_id == other.id


def test_discard_tool_removes_from_inventory_and_cancels_live_session(
    client, session
):
    tool_type = ToolType(
        name="Orbit Survey",
        category="1 site_discovery",
        scientific_tool="satellite",
        description="desc",
        rarity=2,
    )
    session.add(tool_type)
    session.flush()
    owner = _user(session, username="tool_owner")
    other = _user(session, username="tool_other")
    instance = Tool(tool_type_id=int(tool_type.id), level=1, version="Original")
    session.add(instance)
    session.flush()
    session.add(
        UserTool(
            user_id=int(owner.id),
            tool_id=int(instance.id),
            action=USER_TOOL_ACTION_OWNED,
        )
    )
    session.add(
        UserTool(
            user_id=int(other.id),
            tool_id=int(instance.id),
            action=USER_TOOL_ACTION_OWNED,
        )
    )
    live = ToolSession(
        user_id=int(owner.id),
        tool_id=int(instance.id),
        action_key=ACTION_KEY_ORBIT_SURVEY,
        status=SESSION_STATUS_ACTIVE,
        params_json={},
        state_json={},
    )
    session.add(live)
    session.commit()
    instance_id = int(instance.id)
    session_id = int(live.id)

    unauth = client.post(f"/api/v1/tools/{instance_id}/discard")
    assert unauth.status_code in (401, 403)

    discarded = client.post(
        f"/api/v1/tools/{instance_id}/discard",
        headers=_auth_headers(owner),
    )
    assert discarded.status_code == 204

    owner_inventory = client.get(
        "/api/v1/tools",
        params={"mode": "inventory", "sort": "name"},
        headers=_auth_headers(owner),
    )
    assert owner_inventory.status_code == 200
    assert owner_inventory.json()["total"] == 0

    other_inventory = client.get(
        "/api/v1/tools",
        params={"mode": "inventory", "sort": "name"},
        headers=_auth_headers(other),
    )
    assert other_inventory.status_code == 200
    assert other_inventory.json()["total"] == 1
    assert other_inventory.json()["items"][0]["id"] == instance_id

    session.expire_all()
    refreshed = session.get(ToolSession, session_id)
    assert refreshed is not None
    assert refreshed.status == SESSION_STATUS_CANCELLED

    remaining = session.exec(
        select(UserTool).where(col(UserTool.tool_id) == instance_id)
    ).all()
    assert len(remaining) == 1
    assert remaining[0].user_id == other.id


def test_discard_site_removes_caller_links_only(client, session):
    site_type = _seed_site_type(session)
    session.add(
        Site(
            site_id=91001,
            latitude=Decimal("40.000000"),
            longitude=Decimal("-100.000000"),
            formation="Discard Site",
            rock_type="sandstone",
            period="cretaceous",
            site_type_id=site_type.id,
            data_source=DATA_SOURCE_FIELD,
        )
    )
    owner = _user(session, username="site_owner")
    other = _user(session, username="site_other")
    session.add(
        UserSite(
            user_id=int(owner.id),
            site_id=91001,
            role=USER_SITE_ROLE_DISCOVERER,
        )
    )
    session.add(
        UserSite(
            user_id=int(other.id),
            site_id=91001,
            role=USER_SITE_ROLE_DISCOVERER,
        )
    )
    session.commit()

    unauth = client.post("/api/v1/sites/91001/discard")
    assert unauth.status_code in (401, 403)

    discarded = client.post(
        "/api/v1/sites/91001/discard",
        headers=_auth_headers(owner),
    )
    assert discarded.status_code == 204

    owner_list = client.get(
        "/api/v1/sites",
        params={"data_source": "field", "sort": "name"},
        headers=_auth_headers(owner),
    )
    assert owner_list.status_code == 200
    assert owner_list.json()["total"] == 0

    other_list = client.get(
        "/api/v1/sites",
        params={"data_source": "field", "sort": "name"},
        headers=_auth_headers(other),
    )
    assert other_list.status_code == 200
    assert other_list.json()["total"] == 1
    assert other_list.json()["items"][0]["site_id"] == 91001

    remaining = session.exec(
        select(UserSite).where(col(UserSite.site_id) == 91001)
    ).all()
    assert len(remaining) == 1
    assert remaining[0].user_id == other.id


def test_discard_fossil_removes_caller_links_only(client, session):
    dino_type = seed_dinosaur_type(
        session, name="FossilDiscardRex", wikipedia_page_id=900002
    )
    site_type = _seed_site_type(session)
    session.add(
        Site(
            site_id=91002,
            latitude=Decimal("41.000000"),
            longitude=Decimal("-101.000000"),
            formation="Fossil Discard Site",
            rock_type="sandstone",
            period="cretaceous",
            site_type_id=site_type.id,
            data_source=DATA_SOURCE_FIELD,
        )
    )
    session.add(
        Fossil(
            id=210010,
            dinosaur_id=int(dino_type.id),
            identified_name="Discard specimen",
            data_source=DATA_SOURCE_FIELD,
            depth_cm=50,
            llm_enriched=False,
            site_id=91002,
        )
    )
    owner = _user(session, username="fossil_owner")
    other = _user(session, username="fossil_other")
    session.add(
        UserFossil(
            user_id=int(owner.id),
            fossil_id=210010,
            role=USER_FOSSIL_ROLE_IN_SITU,
        )
    )
    session.add(
        UserFossil(
            user_id=int(other.id),
            fossil_id=210010,
            role=USER_FOSSIL_ROLE_IN_SITU,
        )
    )
    session.commit()

    unauth = client.post("/api/v1/fossils/210010/discard")
    assert unauth.status_code in (401, 403)

    discarded = client.post(
        "/api/v1/fossils/210010/discard",
        headers=_auth_headers(owner),
    )
    assert discarded.status_code == 204

    owner_list = client.get(
        "/api/v1/fossils",
        params={"data_source": "field", "sort": "name"},
        headers=_auth_headers(owner),
    )
    assert owner_list.status_code == 200
    assert owner_list.json()["total"] == 0

    other_list = client.get(
        "/api/v1/fossils",
        params={"data_source": "field", "sort": "name"},
        headers=_auth_headers(other),
    )
    assert other_list.status_code == 200
    assert other_list.json()["total"] == 1
    assert other_list.json()["items"][0]["id"] == 210010

    remaining = session.exec(
        select(UserFossil).where(col(UserFossil.fossil_id) == 210010)
    ).all()
    assert len(remaining) == 1
    assert remaining[0].user_id == other.id
