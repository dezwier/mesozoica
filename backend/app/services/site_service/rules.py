"""Transitional alias for the feature-owned implementation."""

import sys

from app.features.sites.application import rules as _implementation

sys.modules[__name__] = _implementation
