"""Compatibility alias for the feature-owned knowledge acquisition job."""

import sys
from app.features.ingestion.jobs import dinosaur_knowledge_acquire as _implementation

sys.modules[__name__] = _implementation
