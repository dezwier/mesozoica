"""Compatibility alias for the field feature model."""

import sys
from app.features.field.models import field_ensure_job as _implementation
sys.modules[__name__] = _implementation
