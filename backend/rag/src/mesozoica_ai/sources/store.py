"""Persist retrieved documents into a SQLModel checkpoint table."""

from __future__ import annotations

import hashlib
import json
from collections.abc import Sequence
from typing import Any, Literal

from mesozoica_ai.common.batch import DEFAULT_SUBJECT_KIND
from mesozoica_ai.common.checkpoints import (
    acquisition_needed,
    begin_acquisition,
    complete_acquisition,
    fail_acquisition,
)
from mesozoica_ai.common.models import Document


def store_documents(
    session: Any,
    model: type[Any],
    *,
    subject: Any,
    source: str,
    documents: Sequence[Document] | None = None,
    error: BaseException | None = None,
    overwrite: bool = False,
    subject_kind: str = DEFAULT_SUBJECT_KIND,
) -> Literal["succeeded", "skipped", "failed"]:
    """Upsert one subject/source row.

    Pass ``documents`` after a successful retrieve, or ``error`` after a failed
    retrieve. Already-succeeded rows are skipped unless ``overwrite`` is set.
    """
    if (documents is None) == (error is None):
        raise ValueError("Provide exactly one of documents or error")

    row = _get_or_create(
        session, model, subject=subject, source=source, subject_kind=subject_kind
    )
    if error is None and not acquisition_needed(row, overwrite=overwrite):
        return "skipped"

    begin_acquisition(row)
    session.add(row)
    session.commit()

    if error is not None:
        fail_acquisition(row, error)
        session.add(row)
        session.commit()
        return "failed"

    complete_acquisition(row, _fingerprinted(documents or ()))
    session.add(row)
    session.commit()
    session.refresh(row)
    return "succeeded"


def _get_or_create(
    session: Any,
    model: type[Any],
    *,
    subject: Any,
    source: str,
    subject_kind: str,
) -> Any:
    from sqlmodel import select

    row = session.exec(
        select(model).where(
            model.subject_kind == subject_kind,
            model.subject_id == str(subject.id),
            model.source == source,
        )
    ).first()
    if row is None:
        row = model(
            subject_kind=subject_kind,
            subject_id=str(subject.id),
            subject_name=subject.name,
            source=source,
        )
        session.add(row)
        session.commit()
        session.refresh(row)
    elif row.subject_name != subject.name:
        row.subject_name = subject.name
    return row


class _Fingerprinted:
    def __init__(
        self,
        *,
        content_hash: str,
        source_hash: str,
        source_version: str | None,
        serialized_documents: list[dict[str, Any]],
    ) -> None:
        self.content_hash = content_hash
        self.source_hash = source_hash
        self.source_version = source_version
        self.serialized_documents = serialized_documents


def _fingerprinted(documents: Sequence[Document]) -> _Fingerprinted:
    serialized = [document.model_dump(mode="json") for document in documents]
    provenance = [
        {
            "id": document.id,
            "source_id": document.metadata.source_id,
            "source_version": document.metadata.source_version,
            "source_url": document.metadata.source_url,
            "published_at": document.metadata.published_at,
            "updated_at": document.metadata.updated_at,
        }
        for document in documents
    ]
    versions = sorted(
        {
            str(document.metadata.source_version)
            for document in documents
            if document.metadata.source_version
        }
    )
    return _Fingerprinted(
        content_hash=_hash_json(serialized),
        source_hash=_hash_json(provenance),
        source_version=",".join(versions)[:255] or None,
        serialized_documents=serialized,
    )


def _hash_json(value: Any) -> str:
    payload = json.dumps(value, sort_keys=True, ensure_ascii=False, default=str).encode(
        "utf-8"
    )
    return hashlib.sha256(payload).hexdigest()
