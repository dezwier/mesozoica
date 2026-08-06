"""Compatibility alias for the feature-owned scheduled job."""

import sys
from app.features.game_config.jobs import game_config_seed as _implementation
sys.modules[__name__] = _implementation
