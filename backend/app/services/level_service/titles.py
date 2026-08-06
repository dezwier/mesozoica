"""Transitional alias for the feature-owned implementation."""

import sys

from app.features.progression.application import titles as _implementation

sys.modules[__name__] = _implementation
