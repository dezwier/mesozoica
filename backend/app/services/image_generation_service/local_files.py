"""Transitional alias for the media-owned implementation."""

import sys

from app.features.media.infrastructure.image_generation import local_files as _implementation

sys.modules[__name__] = _implementation
