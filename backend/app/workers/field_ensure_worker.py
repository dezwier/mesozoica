"""Thin executable adapter for the field-owned ensure worker use case."""

from app.features.field.application.ensure_worker import (  # noqa: F401
    main,
    process_one_ensure_job,
    process_one_job,
    process_one_survey_job,
    run_forever,
)

if __name__ == "__main__":
    main()
