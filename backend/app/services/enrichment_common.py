"""Transitional alias for the feature-owned implementation."""

import sys

from app.features.ingestion.application import enrichment_common as _implementation

sys.modules[__name__] = _implementation
