"""Admin purge of procedural field data (selective scopes)."""

from __future__ import annotations

from dataclasses import dataclass

from sqlalchemy import delete, func
from sqlmodel import Session, col, select

from app.models.data_source import DATA_SOURCE_FIELD
from app.models.field_ensure_job import FieldEnsureJob
from app.models.field_survey_job import FieldSurveyJob
from app.models.fossil import Fossil
from app.models.site import Site
from app.models.tool_mission import ToolMission
from app.models.tool_mission_event import ToolMissionEvent
from app.models.user_fossil import UserFossil
from app.models.user_site import UserSite


@dataclass(frozen=True)
class FieldDataPurgeResult:
    user_sites_deleted: int
    user_fossils_deleted: int
    sites_deleted: int
    fossils_deleted: int
    survey_jobs_deleted: int
    ensure_jobs_deleted: int
    mission_events_deleted: int
    missions_deleted: int


def purge_all_field_data(
    session: Session,
    *,
    user_sites: bool = True,
    user_fossils: bool = True,
    sites: bool = True,
    fossils: bool = True,
    mission_events: bool = True,
    missions: bool = True,
) -> FieldDataPurgeResult:
    """Delete selected field scopes.

    Bulk SQL deletes do not reliably fire ORM cascades (esp. SQLite tests),
    so linked user_site / user_fossil / tool_mission_event rows are removed
    when their parents are deleted even if those checkboxes were left unchecked.
    """
    field_fossil_ids = list(
        session.exec(
            select(Fossil.id).where(col(Fossil.data_source) == DATA_SOURCE_FIELD)
        ).all()
    )
    field_site_ids = list(
        session.exec(
            select(Site.site_id).where(col(Site.data_source) == DATA_SOURCE_FIELD)
        ).all()
    )

    user_fossils_deleted = 0
    fossils_deleted = 0
    if field_fossil_ids and (user_fossils or fossils):
        user_fossils_deleted = _count_user_fossils(session, field_fossil_ids)
        session.exec(
            delete(UserFossil).where(col(UserFossil.fossil_id).in_(field_fossil_ids))
        )
    if fossils and field_fossil_ids:
        fossils_deleted = len(field_fossil_ids)
        session.exec(delete(Fossil).where(col(Fossil.data_source) == DATA_SOURCE_FIELD))

    user_sites_deleted = 0
    sites_deleted = 0
    survey_jobs_deleted = 0
    ensure_jobs_deleted = 0
    mission_events_deleted = 0
    missions_deleted = 0

    if field_site_ids and (user_sites or sites):
        user_sites_deleted = _count_user_sites(session, field_site_ids)
        session.exec(
            delete(UserSite).where(col(UserSite.site_id).in_(field_site_ids))
        )

    # tool_mission_event.site_id → site: clear before deleting field sites.
    if field_site_ids and sites:
        mission_events_deleted += _delete_mission_events_for_sites(
            session, field_site_ids
        )

    if mission_events:
        remaining = int(
            session.exec(select(func.count()).select_from(ToolMissionEvent)).one()
        )
        if remaining:
            session.exec(delete(ToolMissionEvent))
            mission_events_deleted += remaining

    if missions:
        # tool_mission_event.mission_id → tool_mission
        remaining_events = int(
            session.exec(select(func.count()).select_from(ToolMissionEvent)).one()
        )
        if remaining_events:
            session.exec(delete(ToolMissionEvent))
            mission_events_deleted += remaining_events
        missions_deleted = int(
            session.exec(select(func.count()).select_from(ToolMission)).one()
        )
        if missions_deleted:
            session.exec(delete(ToolMission))

    if sites:
        if field_site_ids:
            sites_deleted = len(field_site_ids)
            session.exec(
                delete(Site).where(col(Site.data_source) == DATA_SOURCE_FIELD)
            )
        survey_jobs_deleted = int(
            session.exec(select(func.count()).select_from(FieldSurveyJob)).one()
        )
        if survey_jobs_deleted:
            session.exec(delete(FieldSurveyJob))
        ensure_jobs_deleted = int(
            session.exec(select(func.count()).select_from(FieldEnsureJob)).one()
        )
        if ensure_jobs_deleted:
            session.exec(delete(FieldEnsureJob))

    session.commit()
    return FieldDataPurgeResult(
        user_sites_deleted=user_sites_deleted,
        user_fossils_deleted=user_fossils_deleted,
        sites_deleted=sites_deleted,
        fossils_deleted=fossils_deleted,
        survey_jobs_deleted=survey_jobs_deleted,
        ensure_jobs_deleted=ensure_jobs_deleted,
        mission_events_deleted=mission_events_deleted,
        missions_deleted=missions_deleted,
    )


def _delete_mission_events_for_sites(session: Session, site_ids: list[int]) -> int:
    count = int(
        session.exec(
            select(func.count())
            .select_from(ToolMissionEvent)
            .where(col(ToolMissionEvent.site_id).in_(site_ids))
        ).one()
    )
    if count:
        session.exec(
            delete(ToolMissionEvent).where(
                col(ToolMissionEvent.site_id).in_(site_ids)
            )
        )
    return count


def _count_user_fossils(session: Session, fossil_ids: list[int]) -> int:
    return int(
        session.exec(
            select(func.count())
            .select_from(UserFossil)
            .where(col(UserFossil.fossil_id).in_(fossil_ids))
        ).one()
    )


def _count_user_sites(session: Session, site_ids: list[int]) -> int:
    return int(
        session.exec(
            select(func.count())
            .select_from(UserSite)
            .where(col(UserSite.site_id).in_(site_ids))
        ).one()
    )


__all__ = ["FieldDataPurgeResult", "purge_all_field_data"]
