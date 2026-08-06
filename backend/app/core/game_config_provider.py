"""Compatibility alias for the active game-config provider."""

import sys

from app.features.game_config import provider as _implementation

sys.modules[__name__] = _implementation
