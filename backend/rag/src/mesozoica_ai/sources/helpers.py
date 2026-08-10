"""Shared helpers for source retrieval modules."""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from typing import Any

from mesozoica_ai.common.models import Document


def with_metadata(
    documents: Sequence[Document], metadata: Mapping[str, Any] | None
) -> list[Document]:
    """Return documents with extra metadata fields merged in."""
    if not metadata:
        return list(documents)
    return [
        Document.model_validate(
            {
                **document.model_dump(mode="json"),
                "metadata": {
                    **document.metadata.model_dump(mode="json", exclude_none=True),
                    **metadata,
                },
            }
        )
        for document in documents
    ]
