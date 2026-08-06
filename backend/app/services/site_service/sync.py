"""Transitional alias for the feature-owned implementation."""

import sys

from app.features.sites.application import sync as _implementation

sys.modules[__name__] = _implementation
