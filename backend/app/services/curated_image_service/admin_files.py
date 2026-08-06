"""Transitional alias for the media-owned implementation."""

import sys

from app.features.media.application.curated_images import admin_files as _implementation

sys.modules[__name__] = _implementation
