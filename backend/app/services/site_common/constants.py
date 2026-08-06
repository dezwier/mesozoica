"""Transitional alias for the feature-owned implementation."""

import sys

from app.features.sites.domain import constants as _implementation

sys.modules[__name__] = _implementation
