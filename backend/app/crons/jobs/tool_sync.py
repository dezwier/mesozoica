"""Compatibility alias for the feature-owned scheduled job."""

import sys
from app.features.ingestion.jobs import tool_sync as _implementation
sys.modules[__name__] = _implementation
