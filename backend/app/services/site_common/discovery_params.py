"""Transitional alias for the feature-owned implementation."""

import sys

from app.features.sites.domain import discovery_params as _implementation

sys.modules[__name__] = _implementation
