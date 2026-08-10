"""Cron entry for dinosaur knowledge ingest."""

from app.features.ingestion.jobs.dinosaur_knowledge import run_knowledge_job

__all__ = ["run_knowledge_job"]
