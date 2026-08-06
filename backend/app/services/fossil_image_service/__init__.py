"""Transitional facade for the media-owned package."""

from app.features.media.application.fossil_images import *  # noqa: F403
from app.features.media.application.fossil_images import __all__
from app.features.media.application import fossil_images as _implementation


def __getattr__(name: str):
    return getattr(_implementation, name)
