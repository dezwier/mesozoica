# Mesozoica

Location-based paleontology game (Flutter + FastAPI).

## Mapbox (field map)

The main map tab uses **Mapbox Standard** for both modes:

- **North-fixed** — flat (no tilt), bearing locked to north; pan/zoom free
- **Rotate** — pitched 3D, bearing follows the phone; locked to max zoom and your location (no manual pan/zoom)

Monochrome theme, no place/road/POI labels, and dawn/day/dusk/night from local time. Site markers are simple period-colored circles that tilt with the 3D globe; the full catalog is synced in batches of 500 (not viewport-culled).

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
