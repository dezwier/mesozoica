"""Typed source-acquisition failures."""


class SourceFetchError(Exception):
    """Raised when an external source cannot be fetched or parsed."""
