"""Transitional alias for the feature-owned implementation."""

import sys

from app.shared import data_sources as _implementation

sys.modules[__name__] = _implementation
