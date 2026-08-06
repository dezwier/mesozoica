"""Transitional alias for the feature-owned implementation."""

import sys

from app.features.field.application import field_coordinate_filter as _implementation

sys.modules[__name__] = _implementation
