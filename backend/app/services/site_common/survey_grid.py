"""Transitional alias for the feature-owned implementation."""

import sys

from app.features.sites.domain import survey_grid as _implementation

sys.modules[__name__] = _implementation
