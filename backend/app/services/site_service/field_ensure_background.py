"""Background field-site ensure jobs (non-blocking API path)."""

from __future__ import annotations

import logging
import threading

from sqlmodel import Session

from app.core.database import engine
from app.models.data_source import DATA_SOURCE_FIELD
from app.services.site_service.field_generate import (
    FieldSiteLazyConfig,
    ensure_field_sites_nearby,
)
from app.services.site_service.nearby import count_sites_in_radius

logger = logging.getLogger("field_site_generate")

_lock = threading.Lock()
_active_cells: set[str] = set()


def _cell_key(lat: float, lon: float, radius_km: float) -> str:
    return f"{round(lat, 2)}:{round(lon, 2)}:{radius_km}"


def schedule_field_site_ensure(
    *,
    lat: float,
    lon: float,
    config: FieldSiteLazyConfig | None = None,
) -> tuple[int, int, bool]:
    """Plan and optionally start a background ensure job.

    Returns ``(existing_in_radius, missing, scheduled)``.
    """
    cfg = config or FieldSiteLazyConfig()
    cfg.validate()

    with Session(engine) as session:
        existing = count_sites_in_radius(
            session,
            lat=lat,
            lon=lon,
            radius_km=cfg.radius_km,
            data_source=DATA_SOURCE_FIELD,
        )
    missing = max(0, cfg.min_sites_in_radius - existing)
    if missing == 0:
        return existing, 0, False

    key = _cell_key(lat, lon, cfg.radius_km)
    with _lock:
        if key in _active_cells:
            logger.info(
                "%s action=ensure_skip reason=already_running cell=%s missing=%d",
                "field_site_generate",
                key,
                missing,
            )
            return existing, missing, False
        _active_cells.add(key)

    thread = threading.Thread(
        target=_run_ensure,
        args=(lat, lon, cfg, key),
        daemon=True,
        name=f"field-ensure-{key}",
    )
    thread.start()
    logger.info(
        "%s action=ensure_scheduled cell=%s missing=%d",
        "field_site_generate",
        key,
        missing,
    )
    return existing, missing, True


def _run_ensure(lat: float, lon: float, cfg: FieldSiteLazyConfig, key: str) -> None:
    try:
        with Session(engine) as session:
            ensure_field_sites_nearby(session, lat=lat, lon=lon, config=cfg)
    except Exception:
        logger.exception("%s action=ensure_failed cell=%s", "field_site_generate", key)
    finally:
        with _lock:
            _active_cells.discard(key)
