"""Cron/app entry: acquire SQL snapshots, then index into Azure Search."""

from __future__ import annotations

import importlib.util
from pathlib import Path
from typing import Any

_SCRIPTS = Path(__file__).resolve().parents[3] / "rag" / "scripts"


def _load(name: str, path: Path) -> Any:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise ImportError(f"Unable to load script: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def run_knowledge_job(**kwargs: Any) -> int:
    """Run acquire then index (same pair of rag scripts)."""
    acquire_kwargs = {
        key: kwargs[key]
        for key in ("dry_run", "overwrite", "dinos", "sources", "max_items")
        if key in kwargs
    }
    index_kwargs = {
        key: kwargs[key]
        for key in (
            "dry_run",
            "overwrite",
            "recreate_index",
            "dinos",
            "sources",
            "max_items",
        )
        if key in kwargs
    }
    acquire = _load(
        "mesozoica_acquire_dinosaur_knowledge",
        _SCRIPTS / "01_acquire_dinosaur_knowledge.py",
    ).run(**acquire_kwargs)
    if acquire:
        return acquire
    return _load(
        "mesozoica_index_dinosaur_knowledge",
        _SCRIPTS / "02_index_dinosaur_knowledge.py",
    ).run(**index_kwargs)
