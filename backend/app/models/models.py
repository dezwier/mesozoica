"""
Barrel re-export for SQLModel tables.

Alembic imports this module to detect schema changes.
"""

from app.models.dinosaur import Dinosaur

__all__ = ["Dinosaur"]
