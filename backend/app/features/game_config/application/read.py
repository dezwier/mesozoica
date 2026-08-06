"""Read paths for the stored game config. Feature-owned implementation."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from typing import Optional

from sqlmodel import Session, select

from app.core.game_config import RawDocuments
from app.models.game_config_release import RELEASE_ROW_ID, GameConfigRelease
from app.models.game_config_revision import GameConfigRevision


@dataclass(frozen=True)
class StoredConfig:
    version: int
    checksum: str
    documents: RawDocuments
    activated_at: Optional[datetime]


@dataclass(frozen=True)
class RevisionMeta:
    version: int
    checksum: str
    source: str
    note: str
    created_at: datetime
    created_by_user_id: Optional[int]
    is_active: bool


def read_release(session: Session) -> Optional[GameConfigRelease]:
    return session.get(GameConfigRelease, RELEASE_ROW_ID)


def read_active_version(session: Session) -> Optional[tuple[int, str]]:
    """The hot path: two columns, no document payload."""
    row = session.exec(
        select(
            GameConfigRelease.active_version, GameConfigRelease.active_checksum
        ).where(GameConfigRelease.id == RELEASE_ROW_ID)
    ).first()
    if row is None:
        return None
    return int(row[0]), str(row[1])


def read_active_config(session: Session) -> Optional[StoredConfig]:
    release = read_release(session)
    if release is None:
        return None
    revision = session.get(GameConfigRevision, release.revision_id)
    if revision is None:
        return None
    return StoredConfig(
        version=revision.version,
        checksum=revision.checksum,
        documents=dict(revision.documents),
        activated_at=release.activated_at,
    )


def read_revision(session: Session, version: int) -> Optional[StoredConfig]:
    revision = session.exec(
        select(GameConfigRevision).where(GameConfigRevision.version == version)
    ).first()
    if revision is None:
        return None
    return StoredConfig(
        version=revision.version,
        checksum=revision.checksum,
        documents=dict(revision.documents),
        activated_at=revision.created_at,
    )


def list_revisions(session: Session, *, limit: int = 50) -> list[RevisionMeta]:
    release = read_release(session)
    active_version = release.active_version if release else None
    rows = session.exec(
        select(GameConfigRevision)
        .order_by(GameConfigRevision.version.desc())
        .limit(limit)
    ).all()
    return [
        RevisionMeta(
            version=row.version,
            checksum=row.checksum,
            source=row.source,
            note=row.note,
            created_at=row.created_at,
            created_by_user_id=row.created_by_user_id,
            is_active=row.version == active_version,
        )
        for row in rows
    ]
