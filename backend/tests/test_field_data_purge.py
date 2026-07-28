"""Tests for admin purge of field sites and fossils."""

from __future__ import annotations

from decimal import Decimal

from sqlmodel import Session, col, select

from app.core.security import create_access_token
from app.models.data_source import DATA_SOURCE_ARCHIVE, DATA_SOURCE_FIELD
from app.models.dinosaur import Dinosaur
from app.models.field_ensure_job import FieldEnsureJob
from app.models.field_survey_job import FieldSurveyJob
from app.models.fossil import Fossil
from app.models.site import Site
from app.models.site_type import SiteType
from app.models.tool import Tool
from app.models.tool_type import ToolType
from app.models.tool_mission import ACTION_KEY_AERIAL_RECON, ToolMission
from app.models.tool_mission_event import ToolMissionEvent
from app.models.user import User
from app.models.user_fossil import USER_FOSSIL_ROLE_DISCOVERER, UserFossil
from app.models.user_site import USER_SITE_ROLE_DISCOVERER, UserSite
from app.services.site_service.field_data_purge import purge_all_field_data


def _auth_headers(session: Session, *, username: str, is_admin: bool = False):
    user = User(
        username=username,
        email=f"{username}@example.com",
        password="x",
        is_admin=is_admin,
    )
    session.add(user)
    session.commit()
    session.refresh(user)
    token = create_access_token({"sub": str(user.id)})
    return user, {"Authorization": f"Bearer {token}"}


def _seed_field_world(session: Session) -> tuple[Site, Fossil, User]:
    site_type = SiteType(period="cretaceous", rock_type="sandstone")
    session.add(site_type)
    session.commit()
    session.refresh(site_type)

    archive = Site(
        site_id=42,
        latitude=Decimal("1.0"),
        longitude=Decimal("2.0"),
        period="cretaceous",
        rock_type="sandstone",
        site_type_id=site_type.id,
        data_source=DATA_SOURCE_ARCHIVE,
    )
    field = Site(
        site_id=1_000_000_001,
        latitude=Decimal("40.0"),
        longitude=Decimal("-100.0"),
        period="cretaceous",
        rock_type="sandstone",
        site_type_id=site_type.id,
        data_source=DATA_SOURCE_FIELD,
    )
    session.add(archive)
    session.add(field)
    dino = Dinosaur(
        name="PurgeDino",
        wikipedia_page_id=9001,
        wikipedia_title="PurgeDino",
        birth=70.0,
        death=66.0,
    )
    session.add(dino)
    session.commit()
    session.refresh(dino)

    session.add(
        Fossil(
            id=100,
            dinosaur_id=dino.id,
            site_id=archive.site_id,
            identified_name="archive fossil",
            data_source=DATA_SOURCE_ARCHIVE,
        )
    )
    field_fossil = Fossil(
        id=1_000_000_001,
        dinosaur_id=dino.id,
        site_id=field.site_id,
        identified_name="field fossil",
        data_source=DATA_SOURCE_FIELD,
        depth_cm=0,
    )
    session.add(field_fossil)
    user = User(username="purge_u", email="pu@example.com", password="x")
    session.add(user)
    session.commit()
    session.refresh(user)
    session.add(
        UserSite(
            user_id=user.id,
            site_id=field.site_id,
            role=USER_SITE_ROLE_DISCOVERER,
        )
    )
    session.add(
        UserFossil(
            user_id=user.id,
            fossil_id=1_000_000_001,
            role=USER_FOSSIL_ROLE_DISCOVERER,
        )
    )
    session.add(
        FieldSurveyJob(
            site_id=field.site_id,
            initiated_by_user_id=user.id,
            status="done",
        )
    )
    session.add(
        FieldEnsureJob(
            cell_key="cell-1",
            lat=40.0,
            lon=-100.0,
            radius_km=1.0,
            status="done",
        )
    )
    tool_type = ToolType(
        name="Scout Chopper",
        category="Aircraft",
        scientific_tool="Aerial recon",
        description="Test chopper",
        rarity=1,
        action="Deploy",
    )
    session.add(tool_type)
    session.commit()
    session.refresh(tool_type)
    tool = Tool(tool_type_id=int(tool_type.id), level=1)
    session.add(tool)
    session.commit()
    session.refresh(tool)
    mission = ToolMission(
        user_id=int(user.id),
        tool_id=int(tool.id),
        action_key=ACTION_KEY_AERIAL_RECON,
        status="done",
        route_json='[{"lat":40.0,"lon":-100.0},{"lat":40.1,"lon":-100.0}]',
        route_length_km=11.0,
        flight_duration_s=100,
    )
    session.add(mission)
    session.commit()
    session.refresh(mission)
    session.add(
        ToolMissionEvent(
            mission_id=int(mission.id),
            event_type="discover_site",
            site_id=field.site_id,
            due_at=mission.created_at,
            status="done",
            lat=40.0,
            lon=-100.0,
            distance_along_km=0.0,
        )
    )
    session.commit()
    return field, field_fossil, user


def test_purge_all_field_data_service(session: Session):
    field, field_fossil, _user = _seed_field_world(session)
    field_site_id = field.site_id
    field_fossil_id = field_fossil.id
    result = purge_all_field_data(session)
    assert result.sites_deleted == 1
    assert result.fossils_deleted == 1
    assert result.user_sites_deleted == 1
    assert result.user_fossils_deleted == 1
    assert result.survey_jobs_deleted == 1
    assert result.ensure_jobs_deleted == 1
    assert result.mission_events_deleted == 1
    assert result.missions_deleted == 1

    assert session.get(Site, 42) is not None
    assert session.get(Site, field_site_id) is None
    assert session.get(Fossil, 100) is not None
    assert session.get(Fossil, field_fossil_id) is None
    assert session.exec(select(FieldSurveyJob)).all() == []
    assert session.exec(select(FieldEnsureJob)).all() == []
    assert session.exec(select(ToolMissionEvent)).all() == []
    assert session.exec(select(ToolMission)).all() == []
    assert (
        session.exec(
            select(UserSite).where(col(UserSite.site_id) == field_site_id)
        ).all()
        == []
    )


def test_purge_user_progress_only(session: Session):
    field, field_fossil, user = _seed_field_world(session)
    result = purge_all_field_data(
        session,
        user_sites=True,
        user_fossils=True,
        sites=False,
        fossils=False,
        mission_events=False,
        missions=False,
    )
    assert result.user_sites_deleted == 1
    assert result.user_fossils_deleted == 1
    assert result.sites_deleted == 0
    assert result.fossils_deleted == 0
    assert result.survey_jobs_deleted == 0
    assert result.ensure_jobs_deleted == 0
    assert result.mission_events_deleted == 0
    assert result.missions_deleted == 0

    assert session.get(Site, field.site_id) is not None
    assert session.get(Fossil, field_fossil.id) is not None
    assert (
        session.exec(
            select(UserSite).where(col(UserSite.user_id) == user.id)
        ).all()
        == []
    )
    assert (
        session.exec(
            select(UserFossil).where(col(UserFossil.user_id) == user.id)
        ).all()
        == []
    )
    assert session.exec(select(FieldSurveyJob)).all() != []
    assert session.exec(select(FieldEnsureJob)).all() != []
    assert session.exec(select(ToolMissionEvent)).all() != []
    assert session.exec(select(ToolMission)).all() != []


def test_purge_field_sites_clears_mission_event_fk(session: Session):
    """Deleting sites must remove tool_mission_event rows that reference them."""
    field, _fossil, _user = _seed_field_world(session)
    field_site_id = field.site_id
    result = purge_all_field_data(
        session,
        user_sites=False,
        user_fossils=False,
        sites=True,
        fossils=False,
        mission_events=False,
        missions=False,
    )
    assert result.sites_deleted == 1
    assert result.mission_events_deleted == 1
    assert result.missions_deleted == 0
    assert session.get(Site, field_site_id) is None
    assert session.exec(select(ToolMissionEvent)).all() == []
    assert session.exec(select(ToolMission)).all() != []


def test_purge_missions_only(session: Session):
    _seed_field_world(session)
    result = purge_all_field_data(
        session,
        user_sites=False,
        user_fossils=False,
        sites=False,
        fossils=False,
        mission_events=True,
        missions=True,
    )
    assert result.mission_events_deleted == 1
    assert result.missions_deleted == 1
    assert result.sites_deleted == 0
    assert session.exec(select(ToolMissionEvent)).all() == []
    assert session.exec(select(ToolMission)).all() == []
    assert session.exec(
        select(Site).where(col(Site.data_source) == DATA_SOURCE_FIELD)
    ).all() != []


def test_purge_field_entities_only(session: Session):
    field, field_fossil, _user = _seed_field_world(session)
    field_site_id = field.site_id
    field_fossil_id = field_fossil.id
    result = purge_all_field_data(
        session,
        user_sites=False,
        user_fossils=False,
        sites=True,
        fossils=True,
        mission_events=False,
        missions=False,
    )
    assert result.sites_deleted == 1
    assert result.fossils_deleted == 1
    # Progress + mission events still removed to satisfy FKs when parents go.
    assert result.user_sites_deleted == 1
    assert result.user_fossils_deleted == 1
    assert result.mission_events_deleted == 1
    assert result.missions_deleted == 0
    assert session.get(Site, field_site_id) is None
    assert session.get(Fossil, field_fossil_id) is None
    assert session.exec(select(ToolMission)).all() != []


def test_purge_field_data_api_requires_admin(client, session: Session):
    _user, headers = _auth_headers(session, username="not_admin")
    response = client.delete("/api/v1/sites/field", headers=headers)
    assert response.status_code == 403


def test_purge_field_data_api_admin(client, session: Session):
    site_type = SiteType(period="jurassic", rock_type="mudstone")
    session.add(site_type)
    session.commit()
    session.refresh(site_type)
    session.add(
        Site(
            site_id=1_000_000_099,
            latitude=Decimal("10.0"),
            longitude=Decimal("20.0"),
            period="jurassic",
            rock_type="mudstone",
            site_type_id=site_type.id,
            data_source=DATA_SOURCE_FIELD,
        )
    )
    session.commit()

    _admin, headers = _auth_headers(session, username="admin_purge", is_admin=True)
    response = client.delete("/api/v1/sites/field", headers=headers)
    assert response.status_code == 200
    body = response.json()
    assert body["sites_deleted"] == 1
    assert body["fossils_deleted"] == 0
    assert body["mission_events_deleted"] == 0
    assert body["missions_deleted"] == 0
    assert session.get(Site, 1_000_000_099) is None


def test_purge_field_data_api_rejects_empty_scope(client, session: Session):
    _admin, headers = _auth_headers(session, username="admin_empty", is_admin=True)
    response = client.delete(
        "/api/v1/sites/field",
        headers=headers,
        params={
            "user_sites": "false",
            "user_fossils": "false",
            "sites": "false",
            "fossils": "false",
            "mission_events": "false",
            "missions": "false",
        },
    )
    assert response.status_code == 400
