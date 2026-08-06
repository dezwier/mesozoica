"""Compatibility alias for the sites feature model."""

import sys
from app.features.sites.models import site as _implementation
sys.modules[__name__] = _implementation
