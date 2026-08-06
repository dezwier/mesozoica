# Mesozoica

Location-based paleontology game (Flutter + FastAPI).

For repository-wide onboarding, architecture, domain flows, contracts, and
testing, start at [`../AGENTS.md`](../AGENTS.md) and
[`../docs/README.md`](../docs/README.md). This file is the canonical Flutter
platform and Mapbox setup reference.

## Mapbox (field map)

The main map tab uses **Mapbox Standard** for both modes:

- **North-fixed** — flat (no tilt), bearing locked to north; pan/zoom free
- **Rotate** — pitched 3D, bearing follows the phone; locked to max zoom and your location (no manual pan/zoom)

Monochrome theme, no place/road/POI labels, and dawn/day/dusk/golden_hour/night from local time. Site markers are period-colored circles (north-fixed) or near-user cards (rotate).

**Marker contract** (wipe only on mode/filter toggle; keep-and-diff on pan/zoom; caches for archive / linked / show-all): see [docs/map_site_markers.md](docs/map_site_markers.md).

Card mini-maps still use `flutter_map` + Carto.

| Token | Purpose |
| --- | --- |
| Public `pk.*` | Runtime map loads (`MAPBOX_ACCESS_TOKEN`) |
| Secret `sk.*` with **Downloads:Read** | Download native SDK binaries |

### 1. Public token (runtime)

Tokens live in gitignored [`.dart_defines.json`](.dart_defines.json) (create locally; see example below).

```bash
cd flutter
./run.sh
# or
flutter run --dart-define-from-file=.dart_defines.json
```

`.dart_defines.json` shape:

```json
{
  "MAPBOX_ACCESS_TOKEN": "pk.your_public_token"
}
```

Cursor / VS Code: copy [`.vscode/launch.json.example`](.vscode/launch.json.example) → `.vscode/launch.json` (gitignored) and use F5; the local launch config points at `.dart_defines.json`.


### 2. Secret downloads token (build)

**iOS** — add to `~/.netrc` (chmod 600):

```
machine api.mapbox.com
  login mapbox
  password sk.your_secret_downloads_token
```

**Android** — set env or `~/.gradle/gradle.properties`:

```properties
SDK_REGISTRY_TOKEN=sk.your_secret_downloads_token
```

(`MAPBOX_DOWNLOADS_TOKEN` is accepted as an alias.)

### Billing note

Mobile Maps SDK is billed per monthly active user (MAU). The first 25k MAUs/month are free on Mapbox’s current pay-as-you-go plan. Opening the map tab counts as a Maps SDK MAU.

## Getting started

```bash
cd flutter
flutter pub get
flutter run
```
