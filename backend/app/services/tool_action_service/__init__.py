"""Transitional facade for the feature-owned package."""

from app.features.tools.application.actions import *  # noqa: F403
from app.features.tools.application.actions import __all__
from app.features.tools.application import actions as _implementation


def __getattr__(name: str):
    return getattr(_implementation, name)
