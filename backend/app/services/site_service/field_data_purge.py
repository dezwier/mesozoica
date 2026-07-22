"""Admin purge of all procedural field sites and field fossils."""

from __future__ import annotations

from dataclasses import dataclass

from sqlalchemy import delete, func
from sqlmodel import Session, col, select

from app.models.data_source import DATA_SOURCE_FIELD
from app.models.field_ensure_job import FieldEnsureJob
from app.models.field_survey_job import FieldSurveyJob
from app.models.fossil import Fossil
from app.models.site import Site
from app.models.user_fossil import UserFossil
from app.models.user_site import UserSite


@dataclass(frozen=True)
class FieldDataPurgeResult:
    sites_deleted: int
    fossils_deleted: int
    survey_jobs_deleted: int
    ensure_jobs_deleted: int


def purge_all_field_data(session: Session) -> FieldDataPurgeResult:
    """Delete all field fossils, field sites, and related job rows.

    Bulk SQL deletes do not reliably fire ORM cascades (esp. SQLite tests),
    so linked user_site / user_fossil rows are removed explicitly.
    """
    field_fossil_ids = list(
        session.exec(
            select(Fossil.id).where(col(Fossil.data_source) == DATA_SOURCE_FIELD)
        ).all()
    )
    fossils_deleted = len(field_fossil_ids)
    if field_fossil_ids:
        session.exec(
            delete(UserFossil).where(col(UserFossil.fossil_id).in_(field_fossil_ids))
        )
        session.exec(delete(Fossil).where(col(Fossil.data_source) == DATA_SOURCE_FIELD))

    survey_jobs_deleted = int(
        session.exec(select(func.count()).select_from(FieldSurveyJob)).one()
    )
    if survey_jobs_deleted:
        session.exec(delete(FieldSurveyJob))

    field_site_ids = list(
        session.exec(
            select(Site.site_id).where(col(Site.data_source) == DATA_SOURCE_FIELD)
        ).all()
    )
    sites_deleted = len(field_site_ids)
    if field_site_ids:
        session.exec(
            delete(UserSite).where(col(UserSite.site_id).in_(field_site_ids))
        )
        session.exec(delete(Site).where(col(Site.data_source) == DATA_SOURCE_FIELD))

    ensure_jobs_deleted = int(
        session.exec(select(func.count()).select_from(FieldEnsureJob)).one()
    )
    if ensure_jobs_deleted:
        session.exec(delete(FieldEnsureJob))

    session.commit()
    return FieldDataPurgeResult(
        sites_deleted=sites_deleted,
        fossils_deleted=fossils_deleted,
        survey_jobs_deleted=survey_jobs_deleted,
        ensure_jobs_deleted=ensure_jobs_deleted,
    )


__all__ = ["FieldDataPurgeResult", "purge_all_field_data"]
