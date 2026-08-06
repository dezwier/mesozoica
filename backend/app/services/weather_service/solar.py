"""Compatibility alias for weather solar calculations."""

import sys
from app.features.weather import domain_solar as _implementation
sys.modules[__name__] = _implementation
