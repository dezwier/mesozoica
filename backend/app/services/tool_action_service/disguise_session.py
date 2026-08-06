"""Transitional alias for the feature-owned implementation."""

import sys

from app.features.tools.application.actions import disguise_session as _implementation

sys.modules[__name__] = _implementation
