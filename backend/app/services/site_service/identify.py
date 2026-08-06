"""Transitional alias for the feature-owned implementation."""

import sys

from app.features.sites.application import identify as _implementation

sys.modules[__name__] = _implementation
