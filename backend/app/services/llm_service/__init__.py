"""Transitional facade for the ingestion-owned package."""

from app.features.ingestion.infrastructure.llm import *  # noqa: F403
from app.features.ingestion.infrastructure.llm import __all__
from app.features.ingestion.infrastructure import llm as _implementation


def __getattr__(name: str):
    return getattr(_implementation, name)
