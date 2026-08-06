"""Transitional facade for the feature-owned package."""

from app.features.sites.application import *  # noqa: F403
from app.features.sites.application import __all__
from app.features.sites import application as _implementation


def __getattr__(name: str):
    return getattr(_implementation, name)
