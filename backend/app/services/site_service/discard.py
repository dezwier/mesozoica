"""Discard a field site from the acting user's inventory."""

from __future__ import annotations

from sqlmodel import Session, col, select

from app.core.exceptions import NotFoundError
from app.models.data_source import DATA_SOURCE_FIELD
from app.models.site import Site
from app.models.user_site import UserSite


def discard_site_for_user(
    session: Session,
    *,
    site_id: int,
    user_id: int,
) -> None:
    """Delete the caller's ``user_site`` rows for a field site.

    Idempotent when the caller has no links. Does not affect other users'
    links (unlike status→hidden). The site row is kept.
    """
    site = session.get(Site, site_id)
    if site is None or site.data_source != DATA_SOURCE_FIELD:
        raise NotFoundError(f"Field site {site_id} not found")

    rows = session.exec(
        select(UserSite).where(
            col(UserSite.user_id) == user_id,
            col(UserSite.site_id) == site_id,
        )
    ).all()
    for row in rows:
        session.delete(row)
    if rows:
        session.commit()
