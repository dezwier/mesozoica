# Map site markers

Contract for how excavation sites appear on the Mapbox field map.

## Modes and caches

Three in-memory snapshots in `MapController` (no disk cache):

| Snapshot | Markers mean | Freshness |
|----------|--------------|-----------|
| **Archive** | Full archive catalog | Sticky; soft-refresh after ~7 days without blanking on toggle |
| **Field linked** | Sites linked to the current user (discovered / owned) | Sticky; 60s poll + burst poll after field ensure |
| **Field show-all** (admin) | All field sites in the current viewport | Bbox fetch on map idle; poll reuses last bounds |

Switching Archive ↔ Field or linked ↔ show-all (or map filters) only swaps the active snapshot and the marker `datasetKey`.

## Paint rules

1. **Mode / filter toggle** — wipe circle annotations immediately (`deleteAll`), then paint from the target cache in batches of **500**. Network only if that snapshot is empty or incomplete (or archive is stale).
2. **Pan / zoom / scan / poll** — keep current markers. Create missing ids first, then prune extras. Never blank the map for a same-dataset update.
3. **Show-all viewport** — newer idle bounds **preempt** an in-flight load (`loadSeq`). Warm loads merge pages while fetching; final list replace drives prune after create.
4. **Rotate vs north-fixed** — rotate hides circles (opacity 0) and shows near-user Flutter cards. Circle sync **keeps running** under opacity 0 so exiting rotate does not cold-create thousands of markers.

## Key files

- `lib/controllers/map_controller.dart` — caches, paging, show-all bbox loads
- `lib/widgets/map/mapbox_site_annotations.dart` — wipe / create / prune
- `lib/widgets/map/mapbox_field_map.dart` — debounce, dataset switch, rotate warm path
- `lib/widgets/map/map_visible_bounds.dart` — pad + clamp bbox to API ±180

## Out of scope

- GeoJSON style-layer rewrite
- Durable (Hive / SharedPreferences) site catalogs
- Antimeridian multi-bbox queries
