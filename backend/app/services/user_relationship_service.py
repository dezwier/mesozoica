"""Transitional alias for the feature-owned implementation."""

import sys

from app.features.accounts.application import relationships as _implementation

sys.modules[__name__] = _implementation
