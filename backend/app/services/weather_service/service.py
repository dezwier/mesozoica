"""Compatibility alias for the feature-owned service."""

import sys
from app.features.weather.infrastructure import service as _implementation
sys.modules[__name__] = _implementation
