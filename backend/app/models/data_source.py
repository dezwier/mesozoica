"""Transitional compatibility export for shared provenance identifiers."""

from app.shared.data_sources import (  # noqa: F401
    DATA_SOURCE_ARCHIVE,
    DATA_SOURCE_FIELD,
    DATA_SOURCES,
)

__all__ = ["DATA_SOURCE_ARCHIVE", "DATA_SOURCE_FIELD", "DATA_SOURCES"]
