"""Compatibility alias for the specimens feature API contracts."""

import sys
from app.features.specimens.schemas import dinosaur as _implementation
sys.modules[__name__] = _implementation
