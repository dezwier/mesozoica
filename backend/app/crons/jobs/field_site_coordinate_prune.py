"""Compatibility alias for the feature-owned scheduled job."""

import sys
from app.features.field.jobs import field_site_coordinate_prune as _implementation
sys.modules[__name__] = _implementation
