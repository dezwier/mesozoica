"""Admin purge of procedural field data (selective scopes)."""

from __future__ import annotations

from dataclasses import dataclass

from sqlalchemy import delete, func, update
from sqlalchemy.orm.attributes import flag_modified
from sqlmodel import Session, col, select

from app.models.data_source import DATA_SOURCE_FIELD
from app.models.field_ensure_job import FieldEnsureJob
from app.models.field_survey_job import FieldSurveyJob
from app.models.fossil import Fossil
from app.models.site import Site
from app.models.tool_session import ToolSession
from app.models.tool_session_event import ToolSessionEvent
from app.models.user import User
from app.models.user_fossil import UserFossil
from app.models.user_site import UserSite
from app.services.level_service import sync_career_from_skills
from app.services.level_service.skills import empty_skill_xp, total_skill_xp


@dataclass(frozen=True)
class FieldDataPurgeResult:
    user_sites_deleted: int
    user_fossils_deleted: int
    sites_deleted: int
    fossils_deleted: int
    survey_jobs_deleted: int
    ensure_jobs_deleted: int
    session_events_deleted: int
    sessions_deleted: int
    users_xp_cleared: int = 0
    cleared_xp: int = 0


def purge_all_field_data(
    session: Session,
    *,
    user_sites: bool = True,
    user_fossils: bool = True,
    sites: bool = True,
    fossils: bool = True,
    session_events: bool = True,
    sessions: bool = True,
    xp: bool = False,
) -> FieldDataPurgeResult:
    """Delete selected field scopes.

    Bulk SQL deletes do not reliably fire ORM cascades (esp. SQLite tests),
    so linked user_site / user_fossil / tool_session_event rows are removed
    when their parents are deleted even if those checkboxes were left unchecked.

    When [xp] is true, every user's skill XP / career levels are zeroed.
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
    session_events_deleted = 0
    sessions_deleted = 0

    if field_site_ids and (user_sites or sites):
        user_sites_deleted = _count_user_sites(session, field_site_ids)
        session.exec(
            delete(UserSite).where(col(UserSite.site_id).in_(field_site_ids))
        )

    # Keep denormalized discovery method in sync with discoverer links.
    # Hide-status already clears this; purge of user_sites alone must too.
    if field_site_ids and user_sites and not sites:
        session.exec(
            update(Site)
            .where(col(Site.site_id).in_(field_site_ids))
            .values(how_discovered=None)
        )

    # tool_session_event.site_id → site: clear before deleting field sites.
    if field_site_ids and sites:
        session_events_deleted += _delete_session_events_for_sites(
            session, field_site_ids
        )

    if session_events:
        remaining = int(
            session.exec(select(func.count()).select_from(ToolSessionEvent)).one()
        )
        if remaining:
            session.exec(delete(ToolSessionEvent))
            session_events_deleted += remaining

    if sessions:
        # Events and discoverer FKs must go before tool_session rows.
        remaining_events = int(
            session.exec(select(func.count()).select_from(ToolSessionEvent)).one()
        )
        if remaining_events:
            session.exec(delete(ToolSessionEvent))
            session_events_deleted += remaining_events
        # user_site.source_session_id → tool_session (SET NULL; explicit for SQLite)
        session.exec(
            update(UserSite).values(source_session_id=None)
        )
        sessions_deleted = int(
            session.exec(select(func.count()).select_from(ToolSession)).one()
        )
        if sessions_deleted:
            session.exec(delete(ToolSession))

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

    users_xp_cleared = 0
    cleared_xp = 0
    if xp:
        for user in session.exec(select(User)).all():
            cleared_xp += total_skill_xp(user)
            users_xp_cleared += 1
            user.skill_xp = empty_skill_xp()
            user.skill_breakdown = {}
            flag_modified(user, "skill_xp")
            flag_modified(user, "skill_breakdown")
            sync_career_from_skills(user)
            session.add(user)

    session.commit()
    return FieldDataPurgeResult(
        user_sites_deleted=user_sites_deleted,
        user_fossils_deleted=user_fossils_deleted,
        sites_deleted=sites_deleted,
        fossils_deleted=fossils_deleted,
        survey_jobs_deleted=survey_jobs_deleted,
        ensure_jobs_deleted=ensure_jobs_deleted,
        session_events_deleted=session_events_deleted,
        sessions_deleted=sessions_deleted,
        users_xp_cleared=users_xp_cleared,
        cleared_xp=cleared_xp,
    )


def _delete_session_events_for_sites(session: Session, site_ids: list[int]) -> int:
    count = int(
        session.exec(
            select(func.count())
            .select_from(ToolSessionEvent)
            .where(col(ToolSessionEvent.site_id).in_(site_ids))
        ).one()
    )
    if count:
        session.exec(
            delete(ToolSessionEvent).where(
                col(ToolSessionEvent.site_id).in_(site_ids)
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
