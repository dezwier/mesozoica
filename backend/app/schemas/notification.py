"""Compatibility alias for the accounts feature API contracts."""

import sys
from app.features.accounts.schemas import notification as _implementation
sys.modules[__name__] = _implementation
