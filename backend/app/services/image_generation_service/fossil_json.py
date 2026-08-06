"""Transitional alias for the media-owned implementation."""

import sys

from app.features.media.infrastructure.image_generation import fossil_json as _implementation

sys.modules[__name__] = _implementation
