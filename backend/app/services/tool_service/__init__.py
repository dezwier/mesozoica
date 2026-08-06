"""Transitional facade for the feature-owned package."""

from app.features.tools.application.catalog import *  # noqa: F403
from app.features.tools.application.catalog import __all__
from app.features.tools.application import catalog as _implementation


def __getattr__(name: str):
    return getattr(_implementation, name)
