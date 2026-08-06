"""Compatibility alias for the specimens feature HTTP adapter."""

import sys
from app.features.specimens import api_dinosaurs as _implementation
sys.modules[__name__] = _implementation
