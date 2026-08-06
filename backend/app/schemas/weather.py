"""Compatibility alias for the weather feature API contracts."""

import sys
from app.features.weather.schemas import weather as _implementation
sys.modules[__name__] = _implementation
