"""Helpers for joining the latest user_site row per site (derived status)."""

from __future__ import annotations

from sqlalchemy import and_, func
from sqlmodel import col, select

from app.models.user_site import UserSite


def latest_user_site_subquery():
    """site_id + max(timestamp) for each site."""
    return (
        select(
            col(UserSite.site_id).label("site_id"),
            func.max(col(UserSite.timestamp)).label("max_ts"),
        )
        .group_by(col(UserSite.site_id))
        .subquery()
    )


def latest_user_site_join_condition(latest_user_site: type[UserSite], max_ts_subq):
    """Match UserSite to the latest timestamp row for its site_id."""
    return and_(
        col(latest_user_site.site_id) == max_ts_subq.c.site_id,
        col(latest_user_site.timestamp) == max_ts_subq.c.max_ts,
    )
