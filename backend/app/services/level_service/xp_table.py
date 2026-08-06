"""Transitional alias for the feature-owned implementation."""

import sys

from app.features.progression.application import xp_table as _implementation

sys.modules[__name__] = _implementation
