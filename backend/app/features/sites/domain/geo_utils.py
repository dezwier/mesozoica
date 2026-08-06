"""Transitional alias for the shared geographic primitive."""

import sys

import app.shared.geography.geo_utils as _implementation

sys.modules[__name__] = _implementation
