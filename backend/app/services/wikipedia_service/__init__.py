"""Wikipedia data ingestion for dinosaur master records."""

from app.services.wikipedia_service.sync import sync_dinosaurs, sync_exit_code

__all__ = ["sync_dinosaurs", "sync_exit_code"]
