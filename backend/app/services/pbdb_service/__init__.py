"""Transitional facade for the ingestion-owned package."""

from app.features.ingestion.infrastructure.pbdb import *  # noqa: F403
from app.features.ingestion.infrastructure.pbdb import __all__
from app.features.ingestion.infrastructure import pbdb as _implementation


def __getattr__(name: str):
    return getattr(_implementation, name)
