"""Thin cron wrapper for dinosaur knowledge retrieval evaluation."""

from app.features.ingestion.jobs.dinosaur_knowledge_evaluate import run_evaluate_job

__all__ = ["run_evaluate_job"]
