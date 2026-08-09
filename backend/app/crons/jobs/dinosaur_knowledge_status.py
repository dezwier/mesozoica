"""Compatibility alias for the feature-owned knowledge status job."""

import sys
from app.features.ingestion.jobs import dinosaur_knowledge_status as _implementation

sys.modules[__name__] = _implementation
