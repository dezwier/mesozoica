"""Compatibility alias for the media feature HTTP adapter."""

import sys
from app.features.media import api_tool_images as _implementation
sys.modules[__name__] = _implementation
