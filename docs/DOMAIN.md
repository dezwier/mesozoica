# Domain guide

Mesozoica combines location discovery with a scientific paleontology collection game. This guide explains the vocabulary and state transitions an engineer needs in order to follow code without reverse-engineering the entire UI.

## Core loop

```text
authenticate
  -> choose archive or field discovery
  -> find a site on the map
  -> discover and identify the site
  -> use exploration tools and sessions
  -> surface or collect fossils
  -> grow catalogs and ownership records
  -> earn XP, levels, skill effects, and titles
  -> use improved parameters in later discovery and tool actions
```

The backend is authoritative for permissions, game outcomes, ownership, budgets, and progression. Flutter displays local predictions and cached state but reconciles with server responses.

## Primary concepts

### Accounts and actor context

A user has a profile and one or more authentication identities. Requests use a bearer token; backend authentication resolves that token to the current actor. User-owned state includes discovered sites, fossils, dinosaurs, tools, relationships, notifications, devices, distance, XP, and titles.

### Sites

A site is a geographic excavation location with coordinates, geological dimensions, a site type, and provenance. Two sources matter:

- Archive sites come from catalog/ingestion data and represent known paleontological locations.
- Field sites are procedurally generated around survey cells and use a reserved ID range (`FIELD_SITE_ID_START` and above).

Site state is partly global and partly user-specific. Discovery, identification, documentation/exploration progress, linking, discard state, and visibility must not be inferred from the base site row alone; application services join the latest ownership/status record.

After identifying a site, the viewer documents it by remaining inside the
configurable documentation radius. Each eligible second adds the configured
`document_speed` to every dimension's accuracy; the server records monotonic
unit-interval progress and completes documentation when the average reaches
100% (equivalently, every capped dimension is at 100%).
While an identified site is in range, the client holds a background-location
session so verified fixes continue documenting when the user switches apps or
locks the device. Any suspension gap is reconciled on the first fresh resume
fix when both endpoints remain inside the radius. A terminated process grants
no retrospective documentation time.

The Flutter map can show archive, field, linked, and show-all datasets. These are modes and caches, not synonyms. A server count, a catalog card, and a rendered marker each prove a different stage of the pipeline.

### Site types and dimensions

Site types connect geological period and rock characteristics to display and gameplay metadata. Dimension calculations and display labels are deterministic domain logic. Fallback rules exist when imported data lacks a direct site-type match.

### Field generation and survey cells

The world is partitioned into deterministic geographic cells. A nearby request can schedule an ensure job when a cell lacks enough procedural sites. The long-running field worker claims jobs, generates and filters coordinates, persists sites, and handles retry/state transitions. Survey jobs and ensure jobs are distinct persisted queues.

Coordinate validation can rely on locally cached OSM land/water masks mounted in production. Generating a candidate, storing a site, returning it from an API query, and painting it on the client are separate steps.

### Specimens and collection

Dinosaurs and fossils are catalog entities backed by scientific ingestion. User ownership is represented separately. Catalog browsing does not imply ownership; ownership mutations, discard operations, and collection summaries go through authenticated APIs.

Curated images are versioned media associated with catalog entities. Database metadata, version-list APIs, and static files have separate lifecycles. The repo `images/` directory is the curated source; Railway's mounted volume is the production serving store.

### Tools and expeditions

Tools have catalog definitions, owned instances, parameters, action budgets, and session lifecycles. Actions include timed and spatial experiences such as aerial, guidance, formation, orbit, terrain, disguise, and related sessions. Session events allow restoration and budget accounting. UI controllers coordinate presentation; server application code validates and applies outcomes.

### Progression

Skills accumulate XP and resolve to levels through the leveling configuration. Titles and main parameters derive from progression state. Awards may be triggered by discoveries, collections, actions, and walking distance. Recomputing/backfilling progression is an operational action, not a harmless read.

### Weather and solar periods

Weather is persisted per active geographic cell and refreshed by a scheduled job. Solar-period logic determines ambient presentation and can influence configured parameters. The provider may combine persisted weather, forecast data, and deterministic solar calculations.

### Game configuration

Gameplay configuration is a set of YAML documents, not a single loose dictionary. The backend loads typed sections into an immutable snapshot and stores publishable revisions/releases. Flutter bundles the same documents and parses equivalent typed sections for presentation and prediction.

The server's active version is authoritative. API responses carry `X-Game-Config-Version`; clients send their loaded version so drift can be observed. A config mismatch is logged, not rejected. See the [game-config guide](../backend/app/game_config/README.md).

### Notifications and social relationships

Relationship actions and gameplay events can create notifications and push messages. Firebase-backed delivery is an infrastructure concern; persisted notification state remains the source the client can list and update.

Major site events—discovery, identification, and completed documentation—also
produce celebrations. Their persisted notifications are the cross-lifecycle
source of truth: foreground celebrations become read when shown, while events
created in the background remain unread and queue for ordered presentation on
the next resume.

## Important state distinctions

| Similar-looking concepts | Difference |
| --- | --- |
| Catalog entity vs owned entity | Globally browsable scientific/tool data vs user-specific inventory/state |
| Archive site vs field site | Imported known location vs procedurally generated cell-owned location |
| Site exists vs site is visible | Persistence/query result vs current user/mode/filter visibility |
| Site is visible vs marker is painted | Controller dataset vs successful native-map source reconciliation |
| Tool definition vs user tool | Catalog parameters vs owned instance and mutable budgets |
| Tool action vs tool session | One validated operation vs persisted multi-event lifecycle |
| Config document vs active snapshot | Source YAML/revision vs composed runtime configuration |
| Curated image record vs static image | Version metadata/API state vs file present under `/media/...` |
| Notification record vs push delivery | Durable application state vs best-effort external delivery |

## End-to-end flow: authenticated API request

1. Flutter obtains/restores a token and stores it in the shared token store.
2. A feature controller calls an injected repository.
3. The repository uses the shared API transport, which adds authorization, config version, timeout, decoding, and error mapping.
4. FastAPI resolves the actor and validates the wire schema.
5. A thin router invokes one feature application use case.
6. The use case applies domain rules and coordinates SQL/provider work.
7. The router returns the established response schema.
8. Flutter decodes the DTO/model, updates the appropriate cache, and notifies presentation.

## End-to-end flow: site markers

1. Location and map mode determine the viewport/query strategy.
2. The discovery repository requests sites or schedules field ensure work.
3. The controller updates the mode-specific catalog cache.
4. Selection, filters, show-all/linked state, and viewport logic select a marker dataset.
5. The Mapbox adapter reconciles sources/layers and native annotations in stable order.
6. Optional overlays such as aerial sessions reconcile independently; their failure must not suppress site markers.

The detailed paint and cache rules are a compatibility contract in [`../flutter/docs/map_site_markers.md`](../flutter/docs/map_site_markers.md).

## Scientific data lifecycle

Wikipedia supplies dinosaur article/taxonomy snapshots; PBDB supplies fossil occurrence data; Gemini enriches structured descriptions/measurements and can generate curated image candidates. Ingestion jobs are designed to resume, skip current revisions, and preserve selected curated fields. Media sync then uploads approved files and updates public URLs/version metadata. Read [`../backend/app/crons/README.md`](../backend/app/crons/README.md) before modifying this pipeline.
