"""Transitional alias for the feature-owned implementation."""

import sys

from app.features.ingestion.domain import dinosaur_names as _implementation

sys.modules[__name__] = _implementation
