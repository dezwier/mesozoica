"""Compatibility alias for the specimens feature model."""

import sys
from app.features.specimens.models import fossil as _implementation
sys.modules[__name__] = _implementation
