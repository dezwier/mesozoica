"""Compatibility alias for the weather feature HTTP adapter."""

import sys
from app.features.weather import api_weather as _implementation
sys.modules[__name__] = _implementation
