"""Transitional alias for the feature-owned implementation."""

import sys

from app.features.specimens.application.dinosaurs import list as _implementation

sys.modules[__name__] = _implementation
