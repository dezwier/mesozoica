"""Transitional alias for the feature-owned implementation."""

import sys

from app.features.field.application import field_survey_queue as _implementation

sys.modules[__name__] = _implementation
