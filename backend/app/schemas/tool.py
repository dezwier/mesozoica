"""Compatibility alias for the tools feature API contracts."""

import sys
from app.features.tools.schemas import tool as _implementation
sys.modules[__name__] = _implementation
