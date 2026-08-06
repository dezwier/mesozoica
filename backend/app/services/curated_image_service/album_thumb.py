"""Transitional alias for the media-owned implementation."""

import sys

from app.features.media.application.curated_images import album_thumb as _implementation

sys.modules[__name__] = _implementation
