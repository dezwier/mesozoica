"""Helpers for joining the latest site_status row per site."""

from __future__ import annotations

from sqlalchemy import and_, func
from sqlmodel import col, select

from app.models.site_status import SiteStatus


def latest_site_status_subquery():
    """site_id + max(timestamp) for each site."""
    return (
        select(
            col(SiteStatus.site_id).label("site_id"),
            func.max(col(SiteStatus.timestamp)).label("max_ts"),
        )
        .group_by(col(SiteStatus.site_id))
        .subquery()
    )


def latest_status_join_condition(latest_status: type[SiteStatus], max_ts_subq):
    """Match SiteStatus to the latest timestamp row for its site_id."""
    return and_(
        col(latest_status.site_id) == max_ts_subq.c.site_id,
        col(latest_status.timestamp) == max_ts_subq.c.max_ts,
    )
