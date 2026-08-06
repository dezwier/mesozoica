"""Compatibility entrypoint for the ingestion feature's scheduler."""

import sys

from app.features.ingestion import runner as _implementation

if __name__ == "__main__":
    raise SystemExit(_implementation.main())

sys.modules[__name__] = _implementation
