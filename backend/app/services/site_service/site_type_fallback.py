"""Transitional alias for the feature-owned implementation."""

import sys

from app.features.sites.application import site_type_fallback as _implementation

sys.modules[__name__] = _implementation
