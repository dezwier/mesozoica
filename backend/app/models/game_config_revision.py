"""Compatibility alias for game-config revision persistence."""

import sys
from app.features.game_config import models_revision as _implementation
sys.modules[__name__] = _implementation
