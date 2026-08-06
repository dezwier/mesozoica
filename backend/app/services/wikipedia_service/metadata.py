"""Transitional alias for the ingestion-owned implementation."""

import sys

from app.features.ingestion.infrastructure.wikipedia import metadata as _implementation

sys.modules[__name__] = _implementation
