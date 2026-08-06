"""Transitional alias for the media-owned implementation."""

import sys

from app.features.media.application.dinosaur_generation import generate as _implementation

sys.modules[__name__] = _implementation
