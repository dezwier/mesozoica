"""Compatibility alias for the feature-owned knowledge indexing job."""

import sys
from app.features.ingestion.jobs import dinosaur_knowledge_index as _implementation

sys.modules[__name__] = _implementation
