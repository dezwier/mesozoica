"""Survey a field site: record surveyor role only (fossils come from discovery)."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone

from sqlmodel import Session, col, select

from app.core.exceptions import NotFoundError, ValidationError
from app.models.data_source import DATA_SOURCE_FIELD
from app.models.site import Site
from app.models.user_site import USER_SITE_ROLE_SURVEYOR, UserSite
from app.services.site_service.list import get_site_by_id
from app.services.site_service.summary import SiteRow


@dataclass(frozen=True)
class SurveySiteResult:
    site: SiteRow


def user_has_surveyed(session: Session, *, user_id: int, site_id: int) -> bool:
    row = session.exec(
        select(UserSite).where(
            col(UserSite.user_id) == user_id,
            col(UserSite.site_id) == site_id,
            col(UserSite.role) == USER_SITE_ROLE_SURVEYOR,
        )
    ).first()
    return row is not None


def survey_site(
    session: Session,
    *,
    site_id: int,
    user_id: int,
) -> SurveySiteResult:
    """Record surveyor for ``user_id``. Fossil generation happens on discovery."""
    site = session.get(Site, site_id)
    if site is None or site.data_source != DATA_SOURCE_FIELD:
        raise NotFoundError(f"Field site {site_id} not found")

    period = (site.period or "").strip()
    rock_type = (site.rock_type or "").strip()
    if not period or not rock_type:
        raise ValidationError(
            "Site must have period and rock_type before it can be surveyed"
        )

    _upsert_surveyor(session, user_id=user_id, site_id=site_id)
    site_row = get_site_by_id(
        session,
        site_id,
        data_source=DATA_SOURCE_FIELD,
        viewer_user_id=user_id,
    )
    return SurveySiteResult(site=site_row)


def _upsert_surveyor(
    session: Session, *, user_id: int, site_id: int
) -> UserSite:
    now = datetime.now(timezone.utc)
    existing = session.exec(
        select(UserSite).where(
            col(UserSite.user_id) == user_id,
            col(UserSite.site_id) == site_id,
            col(UserSite.role) == USER_SITE_ROLE_SURVEYOR,
        )
    ).first()
    if existing is None:
        row = UserSite(
            user_id=user_id,
            site_id=site_id,
            role=USER_SITE_ROLE_SURVEYOR,
            timestamp=now,
        )
        session.add(row)
        session.commit()
        session.refresh(row)
        return row

    existing.timestamp = now
    session.add(existing)
    session.commit()
    session.refresh(existing)
    return existing


__all__ = [
    "SurveySiteResult",
    "survey_site",
    "user_has_surveyed",
]
