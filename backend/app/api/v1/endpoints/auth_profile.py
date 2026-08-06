"""Compatibility alias for the accounts feature HTTP adapter."""

import sys
from app.features.accounts import api_auth_profile as _implementation
sys.modules[__name__] = _implementation
