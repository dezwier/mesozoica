"""Compatibility alias for the feature-owned service."""

import sys
from app.features.game_config.application import prune as _implementation
sys.modules[__name__] = _implementation
