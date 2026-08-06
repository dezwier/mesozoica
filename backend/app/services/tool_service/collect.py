"""Transitional alias for the feature-owned implementation."""

import sys

from app.features.tools.application.catalog import collect as _implementation

sys.modules[__name__] = _implementation
