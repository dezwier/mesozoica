"""Transitional facade for the feature-owned package."""

from app.features.progression.application import *  # noqa: F403
from app.features.progression.application import __all__
from app.features.progression import application as _implementation


def __getattr__(name: str):
    return getattr(_implementation, name)
