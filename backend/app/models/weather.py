"""Compatibility alias for weather persistence models."""

import sys

from app.features.weather import models as _implementation

sys.modules[__name__] = _implementation
