"""Compatibility alias for the tools feature model."""

import sys
from app.features.tools.models import user_tool as _implementation
sys.modules[__name__] = _implementation
