"""Fossil read / status services."""

from app.features.specimens.application.fossils.discard import discard_fossil_for_user
from app.features.specimens.application.fossils.list import get_fossil_by_id, list_fossils
from app.features.specimens.application.fossils.set_status import set_fossil_status

__all__ = [
    "discard_fossil_for_user",
    "get_fossil_by_id",
    "list_fossils",
    "set_fossil_status",
]
