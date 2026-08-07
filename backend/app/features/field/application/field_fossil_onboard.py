"""Ensure field fossils on site discovery and award surface (depth 0) locate XP."""

from __future__ import annotations

from dataclasses import dataclass

from sqlmodel import Session, col, select

from app.shared.data_sources import DATA_SOURCE_FIELD
from app.models.field_survey_job import FieldSurveyJob
from app.models.fossil import Fossil
from app.models.site import Site
from app.models.user_site import USER_SITE_ROLE_DISCOVERER, UserSite
from app.features.field.application.field_fossil_generate import count_field_fossils_for_site
from app.features.field.application.field_survey_queue import (
    STATUS_DONE,
    STATUS_PENDING,
    enqueue_field_survey,
    get_field_survey_job,
)
from app.features.sites.public import SiteRow, get_site_by_id


@dataclass(frozen=True)
class DiscoverFossilOnboardResult:
    site: SiteRow
    job_id: int | None
    job_status: str
    onboarded: bool
    generated: bool
    fossils_ready: bool
    surface_fossil_ids: tuple[int, ...]
    celebration: object | None = None


def _surface_fossil_ids(session: Session, *, site_id: int) -> tuple[int, ...]:
    rows = session.exec(
        select(Fossil.id).where(
            col(Fossil.site_id) == site_id,
            col(Fossil.data_source) == DATA_SOURCE_FIELD,
            col(Fossil.depth_cm) == 0,
        )
    ).all()
    return tuple(int(fid) for fid in rows)


def ensure_fossils_on_site_discovery(
    session: Session,
    *,
    site_id: int,
    user_id: int,
) -> DiscoverFossilOnboardResult:
    """Enqueue/onboard global field fossil generation and award surface locate XP.

    Ground-truth fossils are global (once per site). Depth-0 fossils stay in situ
    on the site card for discoverers; ``user_fossil`` is created only when the
    user later extracts them via site actions.
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
        surface_ids = award_surface_locate_to_user(
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
        surface_ids = award_surface_locate_to_user(
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


def award_surface_locate_to_user(
    session: Session,
    *,
    site_id: int,
    user_id: int,
) -> tuple[int, ...]:
    """Award locate-in-situ XP for depth_cm == 0 fossils; return those fossil ids.

    Does not create ``user_fossil`` rows — extraction happens later via site actions.
    XP is idempotent per discoverer via ``UserSite.locate_in_situ_awarded``.
    """
    surface_ids = _surface_fossil_ids(session, site_id=site_id)
    if not surface_ids:
        return ()

    discoverer = session.exec(
        select(UserSite).where(
            col(UserSite.user_id) == user_id,
            col(UserSite.site_id) == site_id,
            col(UserSite.role) == USER_SITE_ROLE_DISCOVERER,
        )
    ).first()
    if discoverer is None:
        return surface_ids

    if not discoverer.locate_in_situ_awarded:
        from app.models.user import User
        from app.features.progression.public import award_fossil_discover_xp

        user = session.get(User, user_id)
        if user is not None:
            weather_time = None
            weather_type = None
            site = session.get(Site, site_id)
            if (
                site is not None
                and site.latitude is not None
                and site.longitude is not None
            ):
                from app.features.weather.public import get_weather, period_at

                lat = float(site.latitude)
                lon = float(site.longitude)
                weather_time = period_at(latitude=lat, longitude=lon)
                try:
                    weather_type = get_weather(lat=lat, lon=lon).weather_type
                except Exception:
                    weather_type = None
            award_fossil_discover_xp(
                user,
                count=len(surface_ids),
                weather_time=weather_time,
                weather_type=weather_type,
            )
            session.add(user)
        discoverer.locate_in_situ_awarded = True
        session.add(discoverer)

    session.commit()
    return surface_ids


def award_surface_locate_to_site_discoverers(
    session: Session,
    *,
    site_id: int,
) -> int:
    """After generation, award depth-0 locate XP to all current site discoverers."""
    discoverer_ids = session.exec(
        select(UserSite.user_id).where(
            col(UserSite.site_id) == site_id,
            col(UserSite.role) == USER_SITE_ROLE_DISCOVERER,
        )
    ).all()
    total = 0
    for user_id in discoverer_ids:
        awarded = award_surface_locate_to_user(
            session, site_id=site_id, user_id=int(user_id)
        )
        total += len(awarded)
    return total


# Back-compat aliases for older call sites / imports.
grant_surface_fossils_to_user = award_surface_locate_to_user
grant_surface_fossils_to_site_discoverers = award_surface_locate_to_site_discoverers


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
    from app.features.specimens.public import fossil_row_to_summary, get_fossil_by_id
    from app.features.sites.public import load_site_types_by_period

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
    "award_surface_locate_to_site_discoverers",
    "award_surface_locate_to_user",
    "ensure_fossils_on_site_discovery",
    "get_field_survey_job",
    "grant_surface_fossils_to_site_discoverers",
    "grant_surface_fossils_to_user",
    "surface_fossil_summaries",
]
