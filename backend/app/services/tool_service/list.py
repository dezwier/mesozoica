"""Query helpers for tool read APIs."""

from __future__ import annotations

import hashlib
from typing import Literal

from sqlalchemy import func, or_
from sqlmodel import Session, col, func as sqlmodel_func, select

from app.core.exceptions import NotFoundError, ValidationError
from app.models.tool import Tool
from app.services.tool_image_service.sync import CURATED_MEDIA_PATH

SortOption = Literal["name", "random", "category"]
_MAX_SEED_LEN = 64


def list_tools(
    session: Session,
    *,
    limit: int = 200,
    offset: int = 0,
    sort: SortOption = "name",
    seed: str | None = None,
    q: str | None = None,
    has_custom_image: bool = False,
) -> tuple[list[Tool], int]:
    """Return paginated tool rows ordered by name or seed-stable random."""
    capped_limit = max(1, min(limit, 500))
    capped_offset = max(0, offset)
    normalized_q = (q or "").strip() or None
    filtered = _filtered_select(
        normalized_q=normalized_q,
        has_custom_image=has_custom_image,
    )

    total = session.exec(
        select(sqlmodel_func.count()).select_from(filtered.subquery())
    ).one()

    if sort == "random":
        normalized_seed = (seed or "").strip()
        if not normalized_seed:
            raise ValidationError("seed is required when sort=random")
        normalized_seed = normalized_seed[:_MAX_SEED_LEN]
        rows = _list_tools_random(
            session,
            filtered=filtered,
            seed=normalized_seed,
            offset=capped_offset,
            limit=capped_limit,
        )
        return rows, int(total)

    order_by = (
        (Tool.category, Tool.name) if sort == "category" else (Tool.name,)
    )
    rows = session.exec(
        filtered.order_by(*order_by).offset(capped_offset).limit(capped_limit)
    ).all()
    return list(rows), int(total)


def _filtered_select(
    *,
    normalized_q: str | None,
    has_custom_image: bool,
):
    stmt = select(Tool)
    if has_custom_image:
        stmt = stmt.where(
            col(Tool.main_image_url).is_not(None),
            col(Tool.main_image_url).contains(CURATED_MEDIA_PATH),
        )
    if normalized_q is not None:
        pattern = f"%{normalized_q}%"
        stmt = stmt.where(
            or_(
                col(Tool.name).ilike(pattern),
                col(Tool.scientific_tool).ilike(pattern),
                col(Tool.category).ilike(pattern),
                col(Tool.description).ilike(pattern),
            )
        )
    return stmt


def _list_tools_random(
    session: Session,
    *,
    filtered,
    seed: str,
    offset: int,
    limit: int,
) -> list[Tool]:
    dialect_name = session.get_bind().dialect.name
    if dialect_name == "postgresql":
        order = func.md5(func.concat(Tool.id, seed))
        rows = session.exec(
            filtered.order_by(order).offset(offset).limit(limit)
        ).all()
        return list(rows)

    all_rows = session.exec(filtered).all()
    all_rows.sort(
        key=lambda row: hashlib.md5(f"{row.id}{seed}".encode()).hexdigest()
    )
    return all_rows[offset : offset + limit]


def get_tool_by_id(session: Session, tool_id: int) -> Tool:
    row = session.get(Tool, tool_id)
    if row is None:
        raise NotFoundError(f"Tool {tool_id} not found")
    return row
