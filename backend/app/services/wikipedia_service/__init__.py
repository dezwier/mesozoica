"""Transitional facade for the ingestion-owned package."""

from app.features.ingestion.infrastructure.wikipedia import *  # noqa: F403
from app.features.ingestion.infrastructure.wikipedia import __all__
from app.features.ingestion.infrastructure import wikipedia as _implementation


def __getattr__(name: str):
    return getattr(_implementation, name)
