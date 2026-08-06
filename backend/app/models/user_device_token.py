"""Compatibility alias for the accounts feature model."""

import sys
from app.features.accounts.models import user_device_token as _implementation
sys.modules[__name__] = _implementation
