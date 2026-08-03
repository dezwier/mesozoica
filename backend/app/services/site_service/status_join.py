"""Helpers for joining the latest user_site row per site (derived status)."""

from __future__ import annotations

from sqlalchemy import and_, func
from sqlmodel import Session, col, select

from app.models.user_site import STATUS_ROLES, UserSite


def latest_user_site_subquery():
    """site_id + max(timestamp) for each site (status roles only).

    Disguiser links are excluded so placing a cover does not overwrite
    lifecycle status.
    """
    return (
        select(
            col(UserSite.site_id).label("site_id"),
            func.max(col(UserSite.timestamp)).label("max_ts"),
        )
        .where(col(UserSite.role).in_(STATUS_ROLES))
        .group_by(col(UserSite.site_id))
        .subquery()
    )


def latest_user_site_join_condition(latest_user_site: type[UserSite], max_ts_subq):
    """Match UserSite to the latest timestamp row for its site_id."""
    return and_(
        col(latest_user_site.site_id) == max_ts_subq.c.site_id,
        col(latest_user_site.timestamp) == max_ts_subq.c.max_ts,
        col(latest_user_site.role).in_(STATUS_ROLES),
    )


def latest_user_sites_for_ids(
    session: Session, site_ids: list[int]
) -> dict[int, UserSite]:
    """Latest ``user_site`` row per site, scoped to ``site_ids`` only.

    Prefer this over [latest_user_site_subquery] for list pages: aggregating
    the full ``user_site`` table on every request saturates the DB pool when
    field density is high (admin show-all viewport).
    """
    if not site_ids:
        return {}
    max_ts = (
        select(
            col(UserSite.site_id).label("site_id"),
            func.max(col(UserSite.timestamp)).label("max_ts"),
        )
        .where(
            col(UserSite.site_id).in_(site_ids),
            col(UserSite.role).in_(STATUS_ROLES),
        )
        .group_by(col(UserSite.site_id))
        .subquery()
    )
    rows = session.exec(
        select(UserSite).join(
            max_ts,
            and_(
                col(UserSite.site_id) == max_ts.c.site_id,
                col(UserSite.timestamp) == max_ts.c.max_ts,
                col(UserSite.role).in_(STATUS_ROLES),
            ),
        )
    ).all()
    return {int(row.site_id): row for row in rows}
