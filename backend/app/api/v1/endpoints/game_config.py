"""Compatibility alias for public game-config endpoints."""

import sys
from app.features.game_config import api_public as _implementation
sys.modules[__name__] = _implementation
