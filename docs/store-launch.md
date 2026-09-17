# Mesozoica store launch

This is the operator checklist for shipping Mesozoica to the App Store and Google Play. Repo work that can be done in git is already in place; everything below needs a human in Apple, Google, Mapbox, Firebase, or a lawyer's chair.

Listing copy: [`store_listing.md`](store_listing.md).
Android build: [`play-store-android-release.md`](play-store-android-release.md).
iOS build: [`app-store-apple-developer-setup.md`](app-store-apple-developer-setup.md).

Public policy pages (canonical; API paths 301 here):

- https://learnfromdata.ai/mesozoica/privacy
- https://learnfromdata.ai/mesozoica/terms
- https://learnfromdata.ai/mesozoica/delete-account
- https://learnfromdata.ai/mesozoica/delete-data

Product / marketing URL: https://learnfromdata.ai/mesozoica

---

## Already done in the repo

- Privacy policy, terms, and deletion instructions.
- Those documents served as HTML from the API and shown in **Profile → Settings → App**.
- Android release signing hooks (`flutter/android/key.properties.example`, `flutter/build_play`).
- Play/App Store listing draft and 512×512 / 1024×500 graphics.
- iOS photo-library usage string, export-compliance flag, and privacy manifest.
- In-app disclosure before the user enables background location.

---

## You must do

### 1. Legal identity (before reviewers ask)

- [ ] Decide the legal name that appears as the seller (your name vs a company).
- [ ] Replace "the operator of Mesozoica" in the policies with that legal name if you want it public.
- [ ] Have counsel skim Terms §18 (governing law is Belgium, liability cap EUR 100, 13+).
- [ ] Confirm `contact@mesozoica.app` receives mail, or change the address in `backend/app/legal/documents/` **and** `flutter/assets/policies/` (they must stay identical).
- [ ] Store consoles should use `https://learnfromdata.ai/mesozoica/...` policy URLs, not the Railway API hostname.

### 2. Font license

- [ ] **TT Ramillas is currently the Trial cut** bundled under `flutter/assets/fonts/tt_ramillas/`. Trial fonts are not licensed for App Store / Play distribution. Buy a commercial license from TypeType, or replace the family before you submit.

### 3. Screenshots (blocked on you capturing the app)

Drop 5 portrait captures into `marketing/app-store/source/` with these names, then run `python3 scripts/generate_app_store_screenshots.py`.

| File | Shot |
| --- | --- |
| `01-map-discovery.jpg` | Map tab with nearby archive/field sites |
| `02-site-card.jpg` | An opened site card / documentation |
| `03-dinosaur-catalog.jpg` | Dinosaur catalog with a turned card |
| `04-fossils-tools.jpg` | Fossil catalog or an active tool session |
| `05-profile-skills.jpg` | Profile with skills / collection |

Capture on:

- iPhone 16 Pro Max / 6.9" simulator (or any tall iPhone; the script frames it)
- Optional iPad 13" if you want iPad screenshots in the first submission

Hide debug account chrome and any `dezwier@mesozoica.app` test UI before capturing. Use a production-looking profile photo and a dense map region.

Play also needs **at least 2 phone screenshots**. You can upload the same 6.9" outputs; Play will accept 1080+ px portraits.

### 4. Google Play

- [ ] Create the Play Console app **Mesozoica**.
- [ ] Create `flutter/android/upload-keystore.jks` and `key.properties` (see the Android release guide).
- [ ] Add the upload-keystore SHA-1 **and later the Play App Signing SHA-1** to the Android OAuth client for `com.mesozoica.mesozoica`.
- [ ] `cd flutter && ./build_play` and upload the AAB to **internal testing** first.
- [ ] Paste listing copy, upload `marketing/play-store/icon-512.png` and `feature-graphic.png`, then screenshots.
- [ ] Set privacy / delete-account / delete-data URLs.
- [ ] Complete Data safety, content rating, target audience, and UGC declarations.
- [ ] For **background location**, upload a screen recording: Settings disclosure → Continue → system Always permission → lock the phone → status-bar notification "Exploring fossil sites" or "Documenting fossil site".
- [ ] Confirm Health Connect / Activity recognition declarations match the walking-distance feature.

### 5. App Store

- [ ] Confirm the App ID `com.desiredewaele.mesozoica` has Sign in with Apple, Push, HealthKit, and matching background modes.
- [ ] Create the App Store Connect record.
- [ ] Archive/upload with the Mapbox token (`flutter build ipa --release --dart-define-from-file=.dart_defines.json`).
- [ ] Attach screenshots, privacy URL, and review notes with a demo login.
- [ ] Explain HealthKit (walking distance only) and Always location (optional, user-toggled) in the review notes.

### 6. Accounts and backend

- [ ] Create a non-admin demo account for reviewers and put it in both consoles' review notes.
- [ ] Smoke-test production: cold-start login, Google, Apple (on a device), map, documentation, catalogs, profile photo, delete-data, delete-account.
- [ ] Confirm `https://learnfromdata.ai/mesozoica/privacy` and `/delete-account` load. API `/privacy` should 301 there.
- [ ] Mapbox production token: use a token restricted to the Mesozoica bundle IDs / Android package, with a usage cap you can live with.

### 7. Reviewer-sensitive product gaps

These are not blockers for *uploading*, but they are common rejection reasons:

- [ ] **Background location on Android** is a restricted permission. If review rejects it, you can ship 1.0 with When-In-Use only and keep Always as a later review. The Settings toggle already fails closed if Always is denied.
- [ ] **UGC**: profiles, photos, and social exist. Play/Apple expect block/report. If those flows are thin, add a visible report path before production, not after the first rejection.
- [ ] **Sign in with Apple** must remain available wherever Google sign-in is offered (already true on iOS).
- [ ] Do not submit a build that still shows the debug test-account filler (`dezwier@mesozoica.app`). That path is debug-only (`kDebugMode`); still verify on a `--release` build.

---

## Identifiers (do not change after first publish)

| Platform | ID | Where |
| --- | --- | --- |
| Android | `com.mesozoica.mesozoica` | Gradle + Firebase Android |
| iOS | `com.desiredewaele.mesozoica` | Xcode + Firebase iOS |
| Version | `1.0.0+1` | `flutter/pubspec.yaml` (`versionName` / `CFBundleShortVersionString` + build number) |

Bump `version:` in `pubspec.yaml` for every store upload (`1.0.0+2`, then `1.0.1+3`, and so on).
