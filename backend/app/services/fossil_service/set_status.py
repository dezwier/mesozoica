"""Transitional alias for the feature-owned implementation."""

import sys

from app.features.specimens.application.fossils import set_status as _implementation

sys.modules[__name__] = _implementation
