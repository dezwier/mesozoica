"""Transitional alias for the ingestion-owned implementation."""

import sys

from app.features.ingestion.application.fossil_enrichment import impute as _implementation

sys.modules[__name__] = _implementation
