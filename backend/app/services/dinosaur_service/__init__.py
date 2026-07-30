"""Dinosaur read / status services."""

from app.services.dinosaur_service.list import get_dinosaur_by_id, list_dinosaurs
from app.services.dinosaur_service.set_status import set_dinosaur_status

__all__ = ["get_dinosaur_by_id", "list_dinosaurs", "set_dinosaur_status"]
