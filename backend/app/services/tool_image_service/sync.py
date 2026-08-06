"""Transitional alias for the media-owned implementation."""

import sys

from app.features.media.application.tool_images import sync as _implementation

sys.modules[__name__] = _implementation
