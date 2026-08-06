"""Transitional alias for the feature-owned implementation."""

import sys

from app.features.specimens.application.dinosaurs import discard as _implementation

sys.modules[__name__] = _implementation
