"""Compatibility alias for the game_config feature API contracts."""

import sys
from app.features.game_config.schemas import game_config as _implementation
sys.modules[__name__] = _implementation
