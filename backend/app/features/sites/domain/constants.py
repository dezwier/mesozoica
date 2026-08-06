"""Transitional alias for the shared geographic primitive."""

import sys

import app.shared.geography.constants as _implementation

sys.modules[__name__] = _implementation
