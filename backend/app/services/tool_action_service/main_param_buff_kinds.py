"""Transitional alias for the feature-owned implementation."""

import sys

from app.features.tools.application.actions import main_param_buff_kinds as _implementation

sys.modules[__name__] = _implementation
