"""Ensure field fossils on site discovery and grant surface (depth 0) discoveries."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone

from sqlmodel import Session, col, select

from app.models.data_source import DATA_SOURCE_FIELD
from app.models.field_survey_job import FieldSurveyJob
from app.models.fossil import Fossil
from app.models.site import Site
from app.models.user_fossil import USER_FOSSIL_ROLE_IN_SITU, UserFossil
from app.models.user_site import USER_SITE_ROLE_DISCOVERER, UserSite
from app.services.field_service.field_fossil_generate import count_field_fossils_for_site
from app.services.field_service.field_survey_queue import (
    STATUS_DONE,
    STATUS_PENDING,
    enqueue_field_survey,
    get_field_survey_job,
)
from app.services.site_service.list import get_site_by_id
from app.services.site_service.summary import SiteRow


@dataclass(frozen=True)
class DiscoverFossilOnboardResult:
    site: SiteRow
    job_id: int | None
    job_status: str
    onboarded: bool
    generated: bool
    fossils_ready: bool
    surface_fossil_ids: tuple[int, ...]


def ensure_fossils_on_site_discovery(
    session: Session,
    *,
    site_id: int,
    user_id: int,
) -> DiscoverFossilOnboardResult:
    """Enqueue/onboard global field fossil generation and grant surface finds.

    Ground-truth fossils are global (once per site). Every discoverer gets
    ``user_fossil`` in_situ rows for depth_cm == 0 when fossils are ready.
    """
    site = session.get(Site, site_id)
    if site is None or site.data_source != DATA_SOURCE_FIELD:
        site_row = get_site_by_id(
            session,
            site_id,
            data_source=DATA_SOURCE_FIELD,
            viewer_user_id=user_id,
        )
        return DiscoverFossilOnboardResult(
            site=site_row,
            job_id=None,
            job_status=STATUS_DONE,
            onboarded=True,
            generated=False,
            fossils_ready=True,
            surface_fossil_ids=(),
        )

    period = (site.period or "").strip()
    rock_type = (site.rock_type or "").strip()
    if not period or not rock_type:
        site_row = get_site_by_id(
            session,
            site_id,
            data_source=DATA_SOURCE_FIELD,
            viewer_user_id=user_id,
        )
        return DiscoverFossilOnboardResult(
            site=site_row,
            job_id=None,
            job_status=STATUS_DONE,
            onboarded=True,
            generated=False,
            fossils_ready=True,
            surface_fossil_ids=(),
        )

    fossil_count = count_field_fossils_for_site(session, site_id)
    if fossil_count > 0:
        surface_ids = grant_surface_fossils_to_user(
            session, site_id=site_id, user_id=user_id
        )
        job = session.exec(
            select(FieldSurveyJob).where(col(FieldSurveyJob.site_id) == site_id)
        ).first()
        site_row = get_site_by_id(
            session,
            site_id,
            data_source=DATA_SOURCE_FIELD,
            viewer_user_id=user_id,
        )
        return DiscoverFossilOnboardResult(
            site=site_row,
            job_id=job.id if job is not None else None,
            job_status=STATUS_DONE if job is None else job.status,
            onboarded=True,
            generated=False,
            fossils_ready=True,
            surface_fossil_ids=surface_ids,
        )

    accepted, job = enqueue_field_survey(session, site_id=site_id, user_id=user_id)
    live_fossil_count = count_field_fossils_for_site(session, site_id)
    # Intentional empty surveys store fossil_count=0. Only re-pend when DONE
    # but fossils are missing despite a positive recorded count (or never recorded).
    if (
        job.status == STATUS_DONE
        and live_fossil_count == 0
        and (job.fossil_count is None or job.fossil_count > 0)
    ):
        job.status = STATUS_PENDING
        job.initiated_by_user_id = user_id
        job.fossil_count = None
        job.worker_id = None
        job.error_message = None
        job.started_at = None
        job.finished_at = None
        session.add(job)
        session.commit()
        session.refresh(job)
        accepted = True
        live_fossil_count = 0

    fossils_ready = job.status == STATUS_DONE and (
        live_fossil_count > 0 or job.fossil_count == 0
    )
    surface_ids: tuple[int, ...] = ()
    if fossils_ready and live_fossil_count > 0:
        surface_ids = grant_surface_fossils_to_user(
            session, site_id=site_id, user_id=user_id
        )

    site_row = get_site_by_id(
        session,
        site_id,
        data_source=DATA_SOURCE_FIELD,
        viewer_user_id=user_id,
    )
    return DiscoverFossilOnboardResult(
        site=site_row,
        job_id=job.id,
        job_status=job.status,
        onboarded=not accepted,
        generated=accepted and job.status == STATUS_PENDING,
        fossils_ready=fossils_ready,
        surface_fossil_ids=surface_ids,
    )


def grant_surface_fossils_to_user(
    session: Session,
    *,
    site_id: int,
    user_id: int,
) -> tuple[int, ...]:
    """Insert in_situ roles for depth_cm == 0 field fossils; return fossil ids."""
    surface = session.exec(
        select(Fossil.id).where(
            col(Fossil.site_id) == site_id,
            col(Fossil.data_source) == DATA_SOURCE_FIELD,
            col(Fossil.depth_cm) == 0,
        )
    ).all()
    if not surface:
        return ()

    existing = set(
        session.exec(
            select(UserFossil.fossil_id).where(
                col(UserFossil.user_id) == user_id,
                col(UserFossil.fossil_id).in_(list(surface)),
                col(UserFossil.role) == USER_FOSSIL_ROLE_IN_SITU,
            )
        ).all()
    )
    now = datetime.now(timezone.utc)
    granted: list[int] = []
    newly_granted = 0
    for fossil_id in surface:
        fid = int(fossil_id)
        if fid in existing:
            granted.append(fid)
            continue
        session.add(
            UserFossil(
                user_id=user_id,
                fossil_id=fid,
                role=USER_FOSSIL_ROLE_IN_SITU,
                timestamp=now,
            )
        )
        newly_granted += 1
        granted.append(fid)

    if newly_granted > 0:
        from app.models.user import User
        from app.services.level_service import award_fossil_discover_xp

        user = session.get(User, user_id)
        if user is not None:
            award_fossil_discover_xp(user, count=newly_granted)
            session.add(user)

    session.commit()
    return tuple(granted)


def grant_surface_fossils_to_site_discoverers(
    session: Session,
    *,
    site_id: int,
) -> int:
    """After generation, grant depth-0 fossils to all current site discoverers."""
    discoverer_ids = session.exec(
        select(UserSite.user_id).where(
            col(UserSite.site_id) == site_id,
            col(UserSite.role) == USER_SITE_ROLE_DISCOVERER,
        )
    ).all()
    total = 0
    for user_id in discoverer_ids:
        granted = grant_surface_fossils_to_user(
            session, site_id=site_id, user_id=int(user_id)
        )
        total += len(granted)
    return total


def surface_fossil_summaries(
    session: Session,
    *,
    fossil_ids: tuple[int, ...],
    viewer_user_id: int | None = None,
):
    """Build FossilSummary list for celebration payloads."""
    if not fossil_ids:
        return []
    # Lazy imports avoid circular dependency with fossil_service.list.
    from app.services.fossil_service.list import fossil_row_to_summary, get_fossil_by_id
    from app.services.site_service.site_type_fallback import load_site_types_by_period

    types_by_period = load_site_types_by_period(session)
    summaries = []
    for fossil_id in fossil_ids:
        try:
            row = get_fossil_by_id(session, fossil_id, data_source=DATA_SOURCE_FIELD)
        except Exception:
            continue
        summaries.append(
            fossil_row_to_summary(
                row,
                types_by_period=types_by_period,
                viewer_user_id=viewer_user_id,
                session=session,
            )
        )
    return summaries


__all__ = [
    "DiscoverFossilOnboardResult",
    "ensure_fossils_on_site_discovery",
    "get_field_survey_job",
    "grant_surface_fossils_to_site_discoverers",
    "grant_surface_fossils_to_user",
    "surface_fossil_summaries",
]
