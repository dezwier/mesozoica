"""Transitional alias for the feature-owned implementation."""

import sys

from app.features.sites.application import reverse_geocode as _implementation

sys.modules[__name__] = _implementation
