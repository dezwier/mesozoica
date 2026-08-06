"""Compatibility alias for the specimens feature model."""

import sys
from app.features.specimens.models import user_dinosaur as _implementation
sys.modules[__name__] = _implementation
