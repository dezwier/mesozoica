"""Dinosaur read / collect services."""

from app.features.specimens.application.dinosaurs.collect import (
    collect_dinosaur_for_user,
    list_dinosaur_image_versions,
)
from app.features.specimens.application.dinosaurs.discard import discard_dinosaur_for_user
from app.features.specimens.application.dinosaurs.list import (
    get_dinosaur_by_id,
    get_dinosaur_with_revision,
    list_dinosaurs,
)

__all__ = [
    "collect_dinosaur_for_user",
    "discard_dinosaur_for_user",
    "get_dinosaur_by_id",
    "get_dinosaur_with_revision",
    "list_dinosaur_image_versions",
    "list_dinosaurs",
]
