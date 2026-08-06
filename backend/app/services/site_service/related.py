"""Transitional alias for the feature-owned implementation."""

import sys

from app.features.sites.application import related as _implementation

sys.modules[__name__] = _implementation
