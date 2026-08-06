"""Transitional facade for the ingestion-owned package."""

from app.features.ingestion.application.dinosaur_enrichment import *  # noqa: F403
from app.features.ingestion.application.dinosaur_enrichment import __all__
from app.features.ingestion.application import dinosaur_enrichment as _implementation


def __getattr__(name: str):
    return getattr(_implementation, name)
