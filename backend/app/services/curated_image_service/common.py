"""Transitional alias for the media-owned implementation."""

import sys

from app.features.media.application.curated_images import common as _implementation

sys.modules[__name__] = _implementation
