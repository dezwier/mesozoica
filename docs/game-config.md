# Game config: architecture & roadmap

The **control board** (`backend/app/game_config/*.yaml`) holds every tunable
game‑mechanics knob — discovery odds, XP, tool modifiers, colors, leveling, etc.
This document describes how it is delivered today and the roadmap toward a single
source of truth that a future **admin web tool** can edit live.

See `backend/app/game_config/README.md` for the meaning of each field.

## Target end state

```
                         ┌──────────────────────────────┐
   Admin web tool ──────▶│  Backend config API           │  ◀── single source of truth
   (future, Phase 4)     │   • Pydantic schema (validate)│
                         │   • DB: versioned control board│
                         └───────────────┬───────────────┘
   GET /api/v1/game-config → {version, config}
   X-Game-Config-Version on responses  ·  FCM "config_updated" push
                         ┌───────────────┼───────────────┐
                 Flutter mobile     Backend rules      (later) admin web
                 (UI / prediction)  (authoritative)    (edits via same API)
```

Three principles:

1. **One schema.** The backend Pydantic `GameConfig` is the canonical schema; the
   Dart model is generated from it (Phase 2) so the two never drift.
2. **One source of values.** The DB (seeded from YAML) becomes the source of
   truth; YAML stays as seed + offline fallback (Phase 3).
3. **Clients fetch at runtime** with a version signal, so tuning ships without an
   app release and can propagate live.

## Current state — Phase 1 (delivered)

The backend now serves the control board over HTTP and the client fetches it at
startup instead of only bundling it. **Values are unchanged**; only delivery moved.

Backend:
- `app/core/game_config.py` — `load_game_config_raw()` returns the raw per‑section
  dict (the exact shape clients parse).
- `app/services/game_config_service.py` — `get_game_config_payload()` validates the
  control board (via the Pydantic `get_game_config()`), then returns
  `{version, config}` where `version` is a stable content hash. Cached
  process‑wide; `clear_game_config_payload_cache()` is the invalidation hook for
  the future write path.
- `GET /api/v1/game-config` (`app/api/v1/endpoints/game_config.py`) — returns the
  payload with an `ETag`; honors `If-None-Match` with `304 Not Modified`.

Flutter:
- `lib/services/game_config_service.dart` — `GameConfigService.initialize()`
  resolves config in order: **API → on‑device cache (shared_preferences) →
  bundled YAML**. Any failure falls through to the next source, so the worst case
  equals the old behavior (bundled assets) and a backend outage never blocks
  startup.
- `lib/config/game_config.dart` — `GameConfig.fromSections(...)` parses the decoded
  JSON payload by reusing the existing per‑section parsers. The
  `GameConfig.instance` accessor is unchanged, so **no call sites changed**.
- `lib/main.dart` calls `GameConfigService.instance.initialize()` instead of
  `GameConfig.load()`.

Wire format: `{ "version": "<hash>", "config": { "site_generation": {…},
"site_discovery": {…}, …, "leveling": {…} } }` — `config` mirrors the YAML files.

## Roadmap

### Phase 2 — Single schema via codegen (removes the duplicated parser)
The backend Pydantic `GameConfig` (~1.8k LOC) and the Flutter parser (~2.0k LOC)
currently define the same schema twice by hand (this is why balance edits need
matching changes in both, and why a few tests drift). Plan:
- Emit JSON Schema / OpenAPI for `GameConfig` from Pydantic (FastAPI already
  produces OpenAPI).
- Generate Dart **data** models from it into `lib/config/generated/`, and keep the
  ergonomic `GameConfig` facade (getters like `siteDiscovery`, computed helpers
  like `resolvedRangeM`) as a thin wrapper so call sites stay put.
- Add a CI check that regenerates and diffs, failing on drift — this is what
  actually enforces single‑source going forward.

### Phase 3 — DB source of truth + live updates
- Table `game_config_version { id, version int (monotonic), payload JSONB,
  is_active, created_by, created_at }`; one active row, history retained for
  audit + rollback. Seeded from YAML as version 1.
- `get_game_config()` reads the active version from the DB (version‑aware cache),
  `clear_game_config_payload_cache()` on write.
- Admin write endpoints (behind `get_current_admin_user`): validate against the
  Pydantic schema (+ range clamps) → insert new immutable version → flip active →
  bump version. `rollback/{version}` for instant revert.
- **Live propagation (two layers):**
  - *Pull:* stamp `X-Game-Config-Version: N` on every API response; clients
    refetch when they see a newer version (no new infra).
  - *Push:* FCM data message `{type: "game_config_updated", version: N}` so idle
    apps update immediately (FCM is already wired up).

### Phase 4 — Admin web tool (future)
A web front end that authenticates as admin and calls the Phase 3 endpoints. It
inherits validation, versioning, rollback, and live push for free — no new
backend. YAML remains an export/DR target.

## Design guarantees to preserve

- **Server stays authoritative.** Server‑enforced params (e.g.
  `visibility_distance_m` on `POST /sites/{id}/discover`, XP awards) take effect
  the moment the active version flips; the client config is for UI/prediction.
  A briefly‑stale client therefore cannot create exploits.
- **Pin config version to in‑flight operations** where math must stay consistent
  across an edit (e.g. store the `config_version` used when a `ToolSession`
  starts). Decide per domain: pin vs. eventual.
- **Validation + guardrails** on every admin write (schema + sane min/max).
- **Offline/first‑launch fallback** always available (bundled YAML).
