"""Transitional alias for the media-owned implementation."""

import sys

from app.features.media.application.curated_images import sync_prune as _implementation

sys.modules[__name__] = _implementation
