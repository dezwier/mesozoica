"""Transitional alias for the ingestion-owned implementation."""

import sys

from app.features.ingestion.infrastructure.wikipedia import sync as _implementation

sys.modules[__name__] = _implementation
