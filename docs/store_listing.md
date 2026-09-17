# Store listing copy

Use this file as the single source for App Store Connect and Google Play listing text. Copy-paste into each console.

Public policy URLs (canonical on learnfromdata.ai; API routes 301 here):

| Field | URL |
| --- | --- |
| Privacy policy | `https://learnfromdata.ai/mesozoica/privacy` |
| Terms | `https://learnfromdata.ai/mesozoica/terms` |
| Delete account URL | `https://learnfromdata.ai/mesozoica/delete-account` |
| Delete data URL | `https://learnfromdata.ai/mesozoica/delete-data` |

Product page / marketing URL: `https://learnfromdata.ai/mesozoica`.

App Store Connect: Privacy Policy URL, Support URL, and Marketing URL as above. Play Console: Policy → App content for privacy and account-deletion URLs; Store settings → Contact details for the website if set.

The same documents are in the app at **Profile → Settings → App → Legal**. API host paths (`/privacy`, …) remain as redirects and must not be used in store consoles.

---

## App name

```
Mesozoica
```

## Subtitle (App Store, max 30 characters)

```
Find fossils where you walk
```

## Short description (Play Store, max 80 characters)

```
Walk the real world, discover fossil sites, and collect dinosaurs.
```

## Promotional text (App Store, max 170 characters)

```
A location-based paleontology game. Discover real and generated fossil sites, excavate with tools, and build a scientifically grounded collection.
```

## Keywords (App Store, comma-separated, max 100 characters)

```
dinosaur,fossil,paleontology,map,walk,museum,science,excavation,collection,gps
```

## Full description (Play Store max 4000 / App Store description)

```
Welcome to Mesozoica — a location-based paleontology game that treats prehistoric life with museum seriousness, not cartoon collecting.

Walk the real world to discover archive sites from the fossil record and generated field sites around you. Document geology, use tools on expeditions, collect fossils, and assemble a catalog of dinosaurs grounded in public scientific sources.

• Discover sites on a live map, including archive localities and nearby field sites.
• Document geology while you stay in range — even with the phone locked, if you enable background exploring.
• Collect fossils and dinosaurs as museum-style cards with facts, cladograms, and deep-time ranges.
• Progress skills and titles as you walk, excavate, and curate.
• Browse catalogs built from Wikipedia, the Paleobiology Database, and curated media.

Mesozoica is built for adults and science enthusiasts. The tone is academic and field-worn: real formations, real taxa, and tools that feel like equipment rather than toys.

The current version is free. Create an account with email, Google, or Sign in with Apple to save your collection across devices.
```

## What's New (1.0.0)

```
First public release: map discovery, fossil and dinosaur catalogs, tools, skills, and account sync.
```

## Store assets in this repo

| Asset | Path | Size |
| --- | --- | --- |
| Play icon | `marketing/play-store/icon-512.png` | 512×512 |
| Feature graphic | `marketing/play-store/feature-graphic.png` | 1024×500 |
| iOS app icon | `flutter/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png` | 1024×1024 |
| Phone screenshots | `marketing/app-store/iphone-6.9/` and `iphone-6.5/` | 1320×2868 / 1284×2778 |
| iPad screenshots | `marketing/app-store/ipad-13/` | 2064×2752 |

Regenerate the Play icon and feature graphic:

```bash
python3 scripts/generate_store_graphics.py
```

After you drop device captures into `marketing/app-store/source/`, compose framed screenshots:

```bash
python3 scripts/generate_app_store_screenshots.py
```
