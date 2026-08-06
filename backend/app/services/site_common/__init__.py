"""Transitional facade for the feature-owned package."""

from app.features.sites.domain import *  # noqa: F403
from app.features.sites.domain import __all__
from app.features.sites import domain as _implementation


def __getattr__(name: str):
    return getattr(_implementation, name)
