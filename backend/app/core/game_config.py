"""Compatibility alias for versioned gameplay configuration."""

import sys

from app.features.game_config import domain as _implementation

sys.modules[__name__] = _implementation
