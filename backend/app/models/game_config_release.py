"""Compatibility alias for game-config release persistence."""

import sys
from app.features.game_config import models_release as _implementation
sys.modules[__name__] = _implementation
