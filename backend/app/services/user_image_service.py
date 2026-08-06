"""Transitional alias for the feature-owned implementation."""

import sys

from app.features.accounts.application import user_images as _implementation

sys.modules[__name__] = _implementation
