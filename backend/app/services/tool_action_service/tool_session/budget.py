"""Transitional alias for the feature-owned implementation."""

import sys

from app.features.tools.application.actions.tool_session import budget as _implementation

sys.modules[__name__] = _implementation
