"""Compatibility alias for the feature-owned quiz preview job."""

import sys
from app.features.ingestion.jobs import dinosaur_quiz_preview as _implementation

sys.modules[__name__] = _implementation
