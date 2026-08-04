"""Publishing new game config revisions."""

from __future__ import annotations

import json
import logging
from typing import Any, Optional

from sqlmodel import Session, select

from app.core.game_config import (
    DOCUMENT_IDS,
    RawDocuments,
    build_game_config,
    canonical_checksum,
)
from app.models.game_config_release import RELEASE_ROW_ID, GameConfigRelease
from app.models.game_config_revision import GameConfigRevision
from app.services.game_config_service.locked_paths import (
    GameConfigLocked,
    assert_locked_paths_unchanged,
)
from app.services.game_config_service.read import StoredConfig, read_active_config

logger = logging.getLogger(__name__)

VALID_SOURCES = frozenset({"seed", "admin", "rollback"})


class GameConfigConflict(RuntimeError):
    """Someone else published while this edit was in flight."""


def normalize_documents(documents: Any) -> RawDocuments:
    """Coerce to the exact JSON shape that will be stored and served.

    Running the round trip *before* validation means what we validate is byte
    for byte what clients later parse — no drift between the two.
    """
    if not isinstance(documents, dict):
        raise ValueError("game config documents must be a mapping")

    missing = [doc_id for doc_id in DOCUMENT_IDS if doc_id not in documents]
    if missing:
        raise ValueError(f"Missing game config documents: {', '.join(missing)}")
    unknown = [doc_id for doc_id in documents if doc_id not in DOCUMENT_IDS]
    if unknown:
        raise ValueError(f"Unknown game config documents: {', '.join(sorted(unknown))}")
    for doc_id, body in documents.items():
        if not isinstance(body, dict):
            raise ValueError(f"game config document '{doc_id}' must be a mapping")

    return json.loads(json.dumps(documents, default=str))


def validate_documents(documents: Any) -> RawDocuments:
    """Structural + full Pydantic validation. Returns the normalized documents."""
    normalized = normalize_documents(documents)
    build_game_config(normalized)  # raises pydantic.ValidationError on bad values
    return normalized


def publish_documents(
    session: Session,
    *,
    documents: Any,
    base_version: Optional[int] = None,
    note: str = "",
    source: str = "admin",
    user_id: Optional[int] = None,
    allow_locked: bool = False,
) -> StoredConfig:
    """Validate and activate a new revision. One transaction, one version bump.

    ``base_version`` is optimistic locking: pass the version the edit started
    from and get a ``GameConfigConflict`` instead of clobbering someone else.
    ``allow_locked`` is for seeding, where the YAML *is* the authority for
    locked paths.
    """
    if source not in VALID_SOURCES:
        raise ValueError(f"unknown game config source: {source}")

    normalized = validate_documents(documents)
    checksum = canonical_checksum(normalized)

    # Lock the singleton release row so concurrent publishes serialize.
    release = session.exec(
        select(GameConfigRelease)
        .where(GameConfigRelease.id == RELEASE_ROW_ID)
        .with_for_update()
    ).first()

    if release is not None:
        if base_version is not None and base_version != release.active_version:
            raise GameConfigConflict(
                f"game config changed since version {base_version} "
                f"(active is {release.active_version})"
            )
        active = read_active_config(session)
        if active is not None and not allow_locked:
            assert_locked_paths_unchanged(normalized, active.documents)
        next_version = release.active_version + 1
    else:
        if base_version is not None:
            raise GameConfigConflict("no active game config to base this edit on")
        next_version = 1

    revision = GameConfigRevision(
        version=next_version,
        documents=normalized,
        checksum=checksum,
        source=source,
        note=note,
        created_by_user_id=user_id,
    )
    session.add(revision)
    session.flush()

    if release is None:
        release = GameConfigRelease(
            id=RELEASE_ROW_ID,
            active_version=revision.version,
            active_checksum=checksum,
            revision_id=revision.id,
            activated_by_user_id=user_id,
        )
        session.add(release)
    else:
        release.active_version = revision.version
        release.active_checksum = checksum
        release.revision_id = revision.id
        release.activated_by_user_id = user_id
        session.add(release)

    session.commit()
    session.refresh(release)

    logger.info(
        "game_config published version=%s source=%s checksum=%s user_id=%s",
        revision.version,
        source,
        checksum[:12],
        user_id,
    )

    # The writing process should see its own change immediately; every other
    # process picks it up on its next version poll.
    from app.core.game_config_provider import invalidate_game_config_cache

    invalidate_game_config_cache()

    return StoredConfig(
        version=revision.version,
        checksum=checksum,
        documents=normalized,
        activated_at=release.activated_at,
    )


def rollback_to_version(
    session: Session,
    *,
    to_version: int,
    note: str = "",
    user_id: Optional[int] = None,
) -> StoredConfig:
    """Republish an old revision's content as a new revision.

    Version only ever moves forward, so client caches and ETags stay monotonic.
    """
    from app.services.game_config_service.read import read_revision

    target = read_revision(session, to_version)
    if target is None:
        raise ValueError(f"unknown game config version: {to_version}")

    return publish_documents(
        session,
        documents=target.documents,
        base_version=None,
        note=note or f"rollback to version {to_version}",
        source="rollback",
        user_id=user_id,
        allow_locked=True,
    )


__all__ = [
    "GameConfigConflict",
    "GameConfigLocked",
    "normalize_documents",
    "publish_documents",
    "rollback_to_version",
    "validate_documents",
]
