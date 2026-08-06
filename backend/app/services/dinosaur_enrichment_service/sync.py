"""Transitional alias for the ingestion-owned implementation."""

import sys

from app.features.ingestion.application.dinosaur_enrichment import sync as _implementation

sys.modules[__name__] = _implementation
