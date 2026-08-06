"""Transitional alias for the ingestion-owned implementation."""

import sys

from app.features.ingestion.infrastructure.llm import client as _implementation

sys.modules[__name__] = _implementation
