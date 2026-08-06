"""Compatibility alias for admin game-config endpoints."""

import sys
from app.features.game_config import api_admin as _implementation
sys.modules[__name__] = _implementation
