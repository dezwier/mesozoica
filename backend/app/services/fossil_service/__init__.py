"""Fossil read / status services."""

from app.services.fossil_service.discard import discard_fossil_for_user
from app.services.fossil_service.list import get_fossil_by_id, list_fossils
from app.services.fossil_service.set_status import set_fossil_status

__all__ = [
    "discard_fossil_for_user",
    "get_fossil_by_id",
    "list_fossils",
    "set_fossil_status",
]
