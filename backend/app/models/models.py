"""
Barrel re-export for SQLModel tables.

Alembic imports this module to detect schema changes.
"""

from app.models.dinosaur import Dinosaur
from app.models.fossil import Fossil

__all__ = ["Dinosaur", "Fossil"]
