"""Transitional facade for the media-owned package."""

from app.features.media.application.dinosaur_generation import *  # noqa: F403
from app.features.media.application.dinosaur_generation import __all__
from app.features.media.application import dinosaur_generation as _implementation


def __getattr__(name: str):
    return getattr(_implementation, name)
