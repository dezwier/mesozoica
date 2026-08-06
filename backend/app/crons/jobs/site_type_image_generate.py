"""Compatibility alias for the feature-owned scheduled job."""

import sys
from app.features.media.jobs import site_type_image_generate as _implementation
sys.modules[__name__] = _implementation
