"""Load cron job definitions from YAML with optional overrides."""

from __future__ import annotations

import os
from pathlib import Path
from typing import Any

import yaml
from pydantic import BaseModel, Field

_PACKAGE_DIR = Path(__file__).resolve().parent
_DEFAULT_CONFIG_PATH = _PACKAGE_DIR / "crons.yaml"


class CronJobDef(BaseModel):
    id: str
    enabled: bool = True
    schedule: str
    params: dict[str, Any] = Field(default_factory=dict)


class CronConfig(BaseModel):
    jobs: list[CronJobDef]


def _deep_merge(base: dict[str, Any], override: dict[str, Any]) -> dict[str, Any]:
    out = dict(base)
    for key, value in override.items():
        if key in out and isinstance(out[key], dict) and isinstance(value, dict):
            out[key] = _deep_merge(out[key], value)
        else:
            out[key] = value
    return out


def _load_yaml(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as handle:
        data = yaml.safe_load(handle)
    if data is None:
        return {}
    if not isinstance(data, dict):
        raise ValueError(f"Invalid cron config (expected mapping): {path}")
    return data


def load_cron_config() -> CronConfig:
    """Load merged cron config: default crons.yaml, optional CRON_CONFIG_PATH overlay, env toggles."""
    if not _DEFAULT_CONFIG_PATH.is_file():
        raise FileNotFoundError(f"Missing default cron config: {_DEFAULT_CONFIG_PATH}")

    merged = _load_yaml(_DEFAULT_CONFIG_PATH)
    extra = os.environ.get("CRON_CONFIG_PATH", "").strip()
    if extra:
        path = Path(extra)
        if not path.is_file():
            raise FileNotFoundError(f"CRON_CONFIG_PATH is not a file: {path}")
        overlay = _load_yaml(path)
        merged = _deep_merge(merged, overlay)

    raw_jobs = merged.get("jobs")
    if not isinstance(raw_jobs, list):
        raise ValueError("cron config must contain a 'jobs' list")

    jobs: list[CronJobDef] = []
    for item in raw_jobs:
        if not isinstance(item, dict):
            continue
        job = CronJobDef.model_validate(item)
        env_key = f"CRON_{job.id.upper().replace('-', '_')}_ENABLED"
        val = os.environ.get(env_key)
        if val is not None:
            job.enabled = val.strip().lower() in ("1", "true", "yes", "on")
        jobs.append(job)

    return CronConfig(jobs=jobs)
