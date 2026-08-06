"""Seed the database from the bundled YAML control board. Feature-owned implementation."""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from typing import Optional

from sqlmodel import Session

from app.core.game_config import canonical_checksum, load_yaml_documents
from app.features.game_config.application.read import read_active_config
from app.features.game_config.application.write import normalize_documents, publish_documents

logger = logging.getLogger(__name__)


@dataclass
class SeedSummary:
    created: bool
    version: int
    checksum: str
    dry_run: bool = False
    changed_doc_ids: list[str] = field(default_factory=list)


def seed_from_yaml(
    session: Session,
    *,
    force: bool = False,
    dry_run: bool = False,
    note: str = "",
    user_id: Optional[int] = None,
) -> SeedSummary:
    """Publish the YAML control board as a revision.

    No-op when a revision already exists unless ``force``; the database is the
    source of truth once seeded, so re-running must not clobber admin edits.
    """
    documents = normalize_documents(load_yaml_documents())
    checksum = canonical_checksum(documents)
    active = read_active_config(session)

    if active is not None:
        changed = sorted(
            doc_id
            for doc_id, body in documents.items()
            if active.documents.get(doc_id) != body
        )
        if not force:
            logger.info(
                "game_config seed skipped (active version=%s, %d document(s) differ)",
                active.version,
                len(changed),
            )
            return SeedSummary(
                created=False,
                version=active.version,
                checksum=active.checksum,
                dry_run=dry_run,
                changed_doc_ids=changed,
            )
        if not changed:
            logger.info("game_config seed --force: YAML already matches active version")
            return SeedSummary(
                created=False,
                version=active.version,
                checksum=active.checksum,
                dry_run=dry_run,
                changed_doc_ids=[],
            )
    else:
        changed = sorted(documents)

    if dry_run:
        logger.info(
            "game_config seed dry-run: would publish %d document(s): %s",
            len(changed),
            ", ".join(changed) or "-",
        )
        return SeedSummary(
            created=False,
            version=(active.version + 1) if active else 1,
            checksum=checksum,
            dry_run=True,
            changed_doc_ids=changed,
        )

    stored = publish_documents(
        session,
        documents=documents,
        base_version=None,
        note=note or "seed from bundled YAML",
        source="seed",
        user_id=user_id,
        # The YAML files are the authority for locked paths by definition.
        allow_locked=True,
    )
    return SeedSummary(
        created=True,
        version=stored.version,
        checksum=stored.checksum,
        dry_run=False,
        changed_doc_ids=changed,
    )


def ensure_seeded() -> None:
    """Publish version 1 on a fresh database. Idempotent, opens its own session."""
    from app.core.database import engine

    with Session(engine) as session:
        if read_active_config(session) is not None:
            return
        summary = seed_from_yaml(session, note="initial seed on startup")
        logger.info("game_config seeded version=%s", summary.version)
