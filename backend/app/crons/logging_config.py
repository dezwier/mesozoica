"""Logging defaults for cron jobs and Wikipedia HTTP client."""

from __future__ import annotations

import logging


def configure_cron_logging(level: int = logging.INFO) -> None:
    """Configure cron runner logging and silence noisy HTTP client logs."""
    logging.basicConfig(level=level, format="%(levelname)s %(message)s", force=True)
    for name in ("httpx", "httpcore", "httpcore.http11", "httpcore.connection"):
        logging.getLogger(name).setLevel(logging.WARNING)
