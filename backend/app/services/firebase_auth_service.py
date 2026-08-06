"""Transitional alias for the feature-owned implementation."""

import sys

from app.features.accounts.infrastructure import firebase_auth as _implementation

sys.modules[__name__] = _implementation
