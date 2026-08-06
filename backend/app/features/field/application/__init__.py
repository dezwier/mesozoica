"""Field site generation, ensure queue, fossils, and coordinate helpers.

Import concrete submodules for heavy dependencies. This package init only
re-exports the most common entry points.
"""

from app.features.field.application.field_ensure_background import schedule_field_site_ensure
from app.features.field.application.field_ensure_queue import (
    cell_key,
    get_field_ensure_job,
)
from app.features.field.application.field_site_logging import log_field_event, normalize_reason
from app.shared.geography import FIELD_SITE_ID_START

__all__ = [
    "FIELD_SITE_ID_START",
    "cell_key",
    "get_field_ensure_job",
    "log_field_event",
    "normalize_reason",
    "schedule_field_site_ensure",
]


def __getattr__(name: str):
    # Lazy to avoid import cycles with site_service during package load.
    if name == "ensure_field_sites_nearby":
        from app.features.field.application.field_generate import ensure_field_sites_nearby

        return ensure_field_sites_nearby
    if name == "FieldSiteLazyConfig":
        from app.features.field.application.field_generate import FieldSiteLazyConfig

        return FieldSiteLazyConfig
    if name == "purge_all_field_data":
        from app.features.field.application.field_data_purge import purge_all_field_data

        return purge_all_field_data
    if name == "get_survey_job":
        from app.features.field.application.field_survey_queue import get_field_survey_job

        return get_field_survey_job
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
