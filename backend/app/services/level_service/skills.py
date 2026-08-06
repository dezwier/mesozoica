"""Transitional alias for the feature-owned implementation."""

import sys

from app.features.progression.application import skills as _implementation

sys.modules[__name__] = _implementation
