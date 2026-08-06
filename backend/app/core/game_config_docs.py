"""Compatibility alias for game-config editorial metadata."""

import sys

from app.features.game_config import metadata as _implementation

sys.modules[__name__] = _implementation
