"""Query helpers for tool read APIs (catalog = tool_type)."""

from __future__ import annotations

import hashlib
import re
from typing import Literal

from sqlalchemy import func, or_
from sqlmodel import Session, col, func as sqlmodel_func, select

from app.core.exceptions import NotFoundError, ValidationError
from app.models.tool import Tool
from app.models.tool_type import ToolType
from app.models.user_tool import USER_TOOL_ACTION_OWNED, UserTool
from app.services.tool_image_service.sync import CURATED_MEDIA_PATH
from app.services.tool_service.collect import ownership_levels_for_tool_types

SortOption = Literal["name", "random", "category"]
_MAX_SEED_LEN = 64
_UNNUMBERED_SEQ = 999_999
_LEADING_SEQ_RE = re.compile(r"^(\d+)\s+(.*)$")


def category_sequence(category: str) -> int:
    """Numeric prefix from category (e.g. '10 reconstruction' → 10)."""
    match = _LEADING_SEQ_RE.match((category or "").strip())
    if match is None:
        return _UNNUMBERED_SEQ
    return int(match.group(1))


def category_display_label(category: str) -> str:
    """Strip leading sequence and title-case (e.g. '1 site_discovery' → 'Site Discovery')."""
    raw = (category or "").strip()
    match = _LEADING_SEQ_RE.match(raw)
    remainder = match.group(2) if match else raw
    words = remainder.replace("_", " ").split()
    return " ".join(word[:1].upper() + word[1:].lower() for word in words if word)


def list_tools(
    session: Session,
    *,
    limit: int = 200,
    offset: int = 0,
    sort: SortOption = "category",
    seed: str | None = None,
    q: str | None = None,
    categories: list[str] | None = None,
    has_custom_image: bool = False,
    viewer_user_id: int | None = None,
    show_all: bool = False,
) -> tuple[list[tuple[ToolType, int | None]], int]:
    """Return paginated (tool_type, level) rows.

    When ``show_all`` is False, only types owned by ``viewer_user_id`` are
    returned (empty if no viewer). When True, the full catalog is returned and
    ``level`` is populated for the viewer when present.
    """
    capped_limit = max(1, min(limit, 500))
    capped_offset = max(0, offset)
    normalized_q = (q or "").strip() or None
    normalized_categories = _normalize_categories(categories)

    if not show_all and viewer_user_id is None:
        return [], 0

    filtered = _filtered_select(
        normalized_q=normalized_q,
        categories=normalized_categories,
        has_custom_image=has_custom_image,
        viewer_user_id=None if show_all else viewer_user_id,
    )

    total = session.exec(
        select(sqlmodel_func.count()).select_from(filtered.subquery())
    ).one()

    if sort == "random":
        normalized_seed = _require_seed(seed)
        rows = _list_tools_random(
            session,
            filtered=filtered,
            seed=normalized_seed,
            offset=capped_offset,
            limit=capped_limit,
        )
    elif sort == "category":
        normalized_seed = _require_seed(seed)
        rows = _list_tools_by_category(
            session,
            filtered=filtered,
            seed=normalized_seed,
            offset=capped_offset,
            limit=capped_limit,
        )
    else:
        rows = list(
            session.exec(
                filtered.order_by(ToolType.name)
                .offset(capped_offset)
                .limit(capped_limit)
            ).all()
        )

    levels: dict[int, int] = {}
    if viewer_user_id is not None:
        levels = ownership_levels_for_tool_types(
            session,
            user_id=viewer_user_id,
            tool_type_ids=[int(row.id) for row in rows if row.id is not None],
        )

    return [
        (row, levels.get(int(row.id)) if row.id is not None else None) for row in rows
    ], int(total)


def list_tool_categories(
    session: Session,
    *,
    viewer_user_id: int | None = None,
    show_all: bool = False,
) -> list[tuple[str, str]]:
    """Distinct categories as (raw_value, display_label), sorted by sequence ASC."""
    if not show_all and viewer_user_id is None:
        return []

    stmt = select(ToolType.category).distinct()
    if not show_all:
        assert viewer_user_id is not None
        stmt = (
            select(ToolType.category)
            .join(Tool, col(Tool.tool_type_id) == col(ToolType.id))
            .join(UserTool, col(UserTool.tool_id) == col(Tool.id))
            .where(
                col(UserTool.user_id) == viewer_user_id,
                col(UserTool.action) == USER_TOOL_ACTION_OWNED,
            )
            .distinct()
        )

    rows = session.exec(stmt).all()
    values = sorted(
        {str(value).strip() for value in rows if value and str(value).strip()},
        key=lambda value: (category_sequence(value), value),
    )
    return [(value, category_display_label(value)) for value in values]


def _normalize_categories(categories: list[str] | None) -> list[str] | None:
    if not categories:
        return None
    cleaned = [value.strip() for value in categories if value and value.strip()]
    return cleaned or None


def _require_seed(seed: str | None) -> str:
    normalized_seed = (seed or "").strip()
    if not normalized_seed:
        raise ValidationError("seed is required when sort=random or sort=category")
    return normalized_seed[:_MAX_SEED_LEN]


def _filtered_select(
    *,
    normalized_q: str | None,
    categories: list[str] | None,
    has_custom_image: bool,
    viewer_user_id: int | None,
):
    stmt = select(ToolType)
    if viewer_user_id is not None:
        stmt = (
            stmt.join(Tool, col(Tool.tool_type_id) == col(ToolType.id))
            .join(
                UserTool,
                (col(UserTool.tool_id) == col(Tool.id))
                & (col(UserTool.user_id) == viewer_user_id)
                & (col(UserTool.action) == USER_TOOL_ACTION_OWNED),
            )
            .distinct()
        )
    if has_custom_image:
        stmt = stmt.where(
            col(ToolType.main_image_url).is_not(None),
            col(ToolType.main_image_url).contains(CURATED_MEDIA_PATH),
        )
    if categories:
        stmt = stmt.where(col(ToolType.category).in_(categories))
    if normalized_q is not None:
        pattern = f"%{normalized_q}%"
        stmt = stmt.where(
            or_(
                col(ToolType.name).ilike(pattern),
                col(ToolType.scientific_tool).ilike(pattern),
                col(ToolType.category).ilike(pattern),
                col(ToolType.description).ilike(pattern),
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
) -> list[ToolType]:
    dialect_name = session.get_bind().dialect.name
    if dialect_name == "postgresql":
        order = func.md5(func.concat(ToolType.id, seed))
        rows = session.exec(
            filtered.order_by(order).offset(offset).limit(limit)
        ).all()
        return list(rows)

    all_rows = session.exec(filtered).all()
    all_rows.sort(
        key=lambda row: hashlib.md5(f"{row.id}{seed}".encode()).hexdigest()
    )
    return all_rows[offset : offset + limit]


def _list_tools_by_category(
    session: Session,
    *,
    filtered,
    seed: str,
    offset: int,
    limit: int,
) -> list[ToolType]:
    """Order by numeric category sequence, then seed-stable shuffle within category."""
    all_rows = list(session.exec(filtered).all())
    all_rows.sort(
        key=lambda row: (
            category_sequence(row.category),
            hashlib.md5(f"{row.id}{seed}".encode()).hexdigest(),
        )
    )
    return all_rows[offset : offset + limit]


def get_tool_by_id(
    session: Session,
    tool_id: int,
    *,
    viewer_user_id: int | None = None,
) -> tuple[ToolType, int | None]:
    row = session.get(ToolType, tool_id)
    if row is None:
        raise NotFoundError(f"Tool {tool_id} not found")
    level: int | None = None
    if viewer_user_id is not None and row.id is not None:
        levels = ownership_levels_for_tool_types(
            session,
            user_id=viewer_user_id,
            tool_type_ids=[int(row.id)],
        )
        level = levels.get(int(row.id))
    return row, level


def tool_to_summary(tool: ToolType, level: int | None = None):
    """Build ToolSummary with optional ownership level (imported lazily to avoid cycles)."""
    from app.schemas.tool import ToolSummary

    return ToolSummary(
        id=int(tool.id),
        name=tool.name,
        category=tool.category,
        scientific_tool=tool.scientific_tool,
        description=tool.description,
        rarity=tool.rarity,
        action=tool.action or "Use",
        main_image_url=tool.main_image_url,
        level=level,
    )
