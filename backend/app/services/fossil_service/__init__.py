"""Transitional facade for the feature-owned package."""

from app.features.specimens.application.fossils import *  # noqa: F403
from app.features.specimens.application.fossils import __all__
from app.features.specimens.application import fossils as _implementation


def __getattr__(name: str):
    return getattr(_implementation, name)
