"""Wikipedia data ingestion for dinosaur master records."""

from app.features.ingestion.infrastructure.wikipedia.sync import sync_dinosaurs, sync_exit_code

__all__ = ["sync_dinosaurs", "sync_exit_code"]
