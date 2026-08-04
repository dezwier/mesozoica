# Bundled curated image version metadata

`meta.yaml` copies (run_date only) for each curated image kind/version.

Shipped inside the Docker image so workers and crons can resolve
`latest_*_image_version()` without the API’s curated-image volume
(Railway volumes are per-service).

Refresh after editing `images/<kind>/<version>/meta.yaml`:

```bash
make sync-bundled-version-meta
```

A unit test fails if bundled run_dates drift from `images/`.
