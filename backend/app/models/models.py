"""
Barrel re-export for SQLModel tables.

Alembic imports this module to detect schema changes.
"""

from app.models.dinosaur import Dinosaur
from app.models.fossil import Fossil
from app.models.site import Site
from app.models.site_type import SiteType

__all__ = ["Dinosaur", "Fossil", "Site", "SiteType"]
