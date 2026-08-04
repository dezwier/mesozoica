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

## Current state — Phases 1 & 2 (delivered)

The backend is the single source of truth: it serves the **canonical, validated**
control board over HTTP, the client fetches it at runtime, and the client's
offline fallback is **generated from the same source** and drift-checked in CI.
Game-mechanics values are unchanged; delivery and enforcement changed.

Backend:
- `app/services/game_config_service.py` — `build_canonical_config()` returns the
  validated, normalized board (`GameConfig.model_dump`); `get_game_config_payload()`
  returns `{version, config}` where `version` is a stable content hash. Cached;
  `clear_game_config_payload_cache()` is the invalidation hook for the future
  write path.
- `GET /api/v1/game-config` (`app/api/v1/endpoints/game_config.py`) — returns the
  payload with an `ETag`; honors `If-None-Match` with `304 Not Modified`.
- `scripts/export_bundled_game_config.py` — regenerates the client's bundled
  snapshot (`flutter/assets/game_config.json`) from the same canonical source.
- `tests/test_game_config_bundled_snapshot.py` — **drift guard**: fails if the
  control board changed without regenerating the snapshot, keeping client and
  server in lockstep.

Flutter:
- `lib/services/game_config_service.dart` — `GameConfigService.initialize()`
  resolves config in order: **API → on-device cache (shared_preferences) →
  bundled canonical snapshot (`assets/game_config.json`) → bundled YAML**. Any
  failure falls through, so a backend outage never blocks startup.
- `lib/config/game_config.dart` — `GameConfig.fromSections(...)` parses the decoded
  JSON via the existing per-section parsers. `GameConfig.instance` is unchanged,
  so **no call sites changed**.
- `test/game_config_snapshot_parity_test.dart` — asserts the canonical snapshot
  parses into every section and equals the YAML control-board projection.

Wire format: `{ "version": "<hash>", "config": { "site_generation": {…},
"site_discovery": {…}, …, "leveling": {…} } }` — `config` is the validated
`GameConfig` (defaults filled, canonical types; e.g. colors as `[r,g,b]`).

### Why the Dart parser was kept (not code-generated away)

The original Phase 2 idea was to generate the Dart model from the Pydantic schema
and delete the hand-written parser. Investigation showed that is **not a safe
mechanical transform**: the Dart `game_config.dart` is a *bespoke client
projection*, not a 1:1 mirror of the backend schema. It (a) models a **subset**
(the backend has server-only defs like `SiteGenerationBulkConfig`,
`FossilGenerationDefaults`), (b) uses **different ergonomics** (e.g. it lifts
`lazy.cell_size_m` up to `cellSizeM`, exposes computed helpers like
`resolvedRangeM`, `defaultsForToolName`, modifier resolution), and (c) its types
are a **widely-used public API** — `ParamModifier`, `SkillStubConfig`,
`ModifiesMainParams`, etc. are constructed 130+ times across app and tests.

Generating from the full schema would produce a different, wrong API and risk
gameplay-balance regressions that can't be fully validated headlessly. Instead we
made the backend authoritative for values/defaults (canonical serving) and added
an **automatic drift guard** (generated snapshot + parity tests) — which removes
the actual pain (silent client/server drift) without a risky rewrite. Fully
unifying the two into one generated model is still possible but belongs behind a
shared **neutral schema** (see Phase 2b), as a separate, carefully-reviewed change.

## Roadmap

### Phase 2b — Optional full unification via a shared neutral schema (future)
Phase 2 delivered canonical serving + a generated, drift-checked client snapshot,
which removes silent drift. If we later want to eliminate the *duplicated field
declarations* entirely (not just guard them), the safe path is:
- Define the schema once in a neutral spec (JSON Schema / protobuf).
- Generate **both** the Pydantic models and the Dart **data** classes from it,
  keeping the ergonomic Dart facade (computed helpers) hand-written on top.
- Keep the CI drift guard as the safety net during migration.
This is deferred because the current Dart model is a bespoke projection (see "Why
the Dart parser was kept" above), so unification is a larger, separately-reviewed
change rather than a mechanical codegen.

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
