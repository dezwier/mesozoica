"""Process-wide game config snapshot, backed by the database.

Deliberately separate from ``game_config.py`` so that module stays free of any
database import — the minimal-settings worker and the DB-free tests depend on
being able to load and validate config from YAML alone.

Cross-process invalidation without Redis: each process caches a snapshot plus
the time it last checked. Past ``GAME_CONFIG_REFRESH_S`` it re-reads two
columns from ``game_config_release``; only a version change pulls the full
document bundle. Staleness is bounded by that TTL identically for the API, the
cron service, and the long-running worker.
"""

from __future__ import annotations

import logging
import os
import threading
import time
from dataclasses import dataclass
from datetime import datetime
from typing import Literal, Optional

from app.core.game_config import (
    GameConfig,
    RawDocuments,
    build_game_config,
    canonical_checksum,
    load_yaml_documents,
)

logger = logging.getLogger(__name__)

SnapshotSource = Literal["yaml", "db", "db-stale"]

# "yaml" is the break-glass path: set it on Railway and restart to run every
# service off the bundled control board without touching the database.
GAME_CONFIG_SOURCE = os.getenv("GAME_CONFIG_SOURCE", "db").strip().lower()
GAME_CONFIG_REFRESH_S = float(os.getenv("GAME_CONFIG_REFRESH_S", "15"))

# Version 0 means "not from the database" — the bundled YAML floor.
YAML_VERSION = 0

_ERROR_LOG_INTERVAL_S = 60.0


@dataclass(frozen=True)
class GameConfigSnapshot:
    config: GameConfig
    documents: RawDocuments
    version: int
    checksum: str
    source: SnapshotSource
    activated_at: Optional[datetime] = None

    @property
    def etag(self) -> str:
        return f'"cfg-{self.version}-{self.checksum[:12]}"'


_lock = threading.Lock()
_snapshot: Optional[GameConfigSnapshot] = None
_checked_at: float = 0.0
_last_error_log_at: float = 0.0


def _log_error_throttled(message: str, error: BaseException) -> None:
    global _last_error_log_at
    now = time.monotonic()
    if now - _last_error_log_at < _ERROR_LOG_INTERVAL_S:
        return
    _last_error_log_at = now
    logger.warning("%s: %s", message, error)


def _yaml_snapshot() -> GameConfigSnapshot:
    documents = load_yaml_documents()
    return GameConfigSnapshot(
        config=build_game_config(documents),
        documents=documents,
        version=YAML_VERSION,
        checksum=canonical_checksum(documents),
        source="yaml",
    )


def _db_snapshot() -> Optional[GameConfigSnapshot]:
    """Current stored config, or None when nothing has been seeded yet."""
    from sqlmodel import Session

    from app.core.database import engine
    from app.services.game_config_service.read import read_active_config

    with Session(engine) as session:
        stored = read_active_config(session)
    if stored is None:
        return None
    return GameConfigSnapshot(
        config=build_game_config(stored.documents),
        documents=stored.documents,
        version=stored.version,
        checksum=stored.checksum,
        source="db",
        activated_at=stored.activated_at,
    )


def _db_active_version() -> Optional[tuple[int, str]]:
    from sqlmodel import Session

    from app.core.database import engine
    from app.services.game_config_service.read import read_active_version

    with Session(engine) as session:
        return read_active_version(session)


def _stale(snapshot: GameConfigSnapshot) -> GameConfigSnapshot:
    if snapshot.source == "db-stale":
        return snapshot
    return GameConfigSnapshot(
        config=snapshot.config,
        documents=snapshot.documents,
        version=snapshot.version,
        checksum=snapshot.checksum,
        source="db-stale",
        activated_at=snapshot.activated_at,
    )


def get_active_snapshot() -> GameConfigSnapshot:
    """The config this process should use. Never raises on database trouble."""
    global _snapshot, _checked_at

    if GAME_CONFIG_SOURCE == "yaml":
        with _lock:
            if _snapshot is None or _snapshot.source != "yaml":
                _snapshot = _yaml_snapshot()
            return _snapshot

    with _lock:
        cached = _snapshot
        fresh = cached is not None and (
            time.monotonic() - _checked_at < GAME_CONFIG_REFRESH_S
        )
        if fresh:
            return cached  # type: ignore[return-value]

        try:
            active = _db_active_version()
            if active is None:
                # Nothing seeded yet — fall back to the bundled control board,
                # but keep re-checking so the first seed is picked up.
                _snapshot = cached if cached is not None else _yaml_snapshot()
                _checked_at = time.monotonic()
                return _snapshot

            version, checksum = active
            if (
                cached is not None
                and cached.source != "yaml"
                and cached.version == version
                and cached.checksum == checksum
            ):
                _checked_at = time.monotonic()
                return cached

            loaded = _db_snapshot()
            if loaded is None:
                _snapshot = cached if cached is not None else _yaml_snapshot()
                _checked_at = time.monotonic()
                return _snapshot

            _snapshot = loaded
            _checked_at = time.monotonic()
            return loaded
        except Exception as error:  # noqa: BLE001 - config must never hard-fail
            _log_error_throttled("game_config database read failed", error)
            if cached is not None:
                # Keep serving the last good config; do not advance _checked_at
                # so the next call retries.
                _snapshot = _stale(cached)
                return _snapshot
            _snapshot = _yaml_snapshot()
            return _snapshot


def invalidate_game_config_cache() -> None:
    """Force the next access to re-read. Called after a publish and by tests."""
    global _snapshot, _checked_at, _last_error_log_at
    with _lock:
        _snapshot = None
        _checked_at = 0.0
        _last_error_log_at = 0.0


def get_active_documents() -> RawDocuments:
    return get_active_snapshot().documents
