"""Transitional facade for the media-owned package."""

from app.features.media.infrastructure.image_generation import *  # noqa: F403
from app.features.media.infrastructure.image_generation import __all__
from app.features.media.infrastructure import image_generation as _implementation


def __getattr__(name: str):
    return getattr(_implementation, name)
