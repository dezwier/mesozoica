"""Transitional alias for the feature-owned implementation."""

import sys

from app.features.accounts.application import walk_distance as _implementation

sys.modules[__name__] = _implementation
