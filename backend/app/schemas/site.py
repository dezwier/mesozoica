"""Compatibility alias for the sites feature API contracts."""

import sys
from app.features.sites.schemas import site as _implementation
sys.modules[__name__] = _implementation
