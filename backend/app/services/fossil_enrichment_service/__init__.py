"""Transitional facade for the ingestion-owned package."""

from app.features.ingestion.application.fossil_enrichment import *  # noqa: F403
from app.features.ingestion.application.fossil_enrichment import __all__
from app.features.ingestion.application import fossil_enrichment as _implementation


def __getattr__(name: str):
    return getattr(_implementation, name)
