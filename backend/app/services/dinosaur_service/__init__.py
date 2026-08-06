"""Transitional facade for the feature-owned package."""

from app.features.specimens.application.dinosaurs import *  # noqa: F403
from app.features.specimens.application.dinosaurs import __all__
from app.features.specimens.application import dinosaurs as _implementation


def __getattr__(name: str):
    return getattr(_implementation, name)
