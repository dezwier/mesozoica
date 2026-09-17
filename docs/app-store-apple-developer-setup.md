# Apple Developer and App Store Connect (Mesozoica)

iOS bundle ID: **`com.desiredewaele.mesozoica`**.

This ID is already used in Xcode (`DEVELOPMENT_TEAM = RT8QQM75RF`), Sign in with Apple entitlements, and Firebase (`flutter/ios/Runner/GoogleService-Info.plist`). Do not change it.

## Prerequisites

- Apple Developer Program membership ($99/year).
- The same Apple ID you use in Xcode for signing.

---

## 1. App ID

1. Open [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list).
2. Register an **App ID** of type **App**.
3. Bundle ID: explicit **`com.desiredewaele.mesozoica`**.
4. Enable:
   - **Sign in with Apple** (already in `Runner.entitlements`).
   - **Push Notifications**.
   - **HealthKit**.
   - Background Modes are configured in `Info.plist` (`location`, `remote-notification`); enable them on the App ID / Xcode capability list to match.

If the App ID already exists from earlier development, verify those capabilities are checked and saved.

---

## 2. App Store Connect record

1. Open [App Store Connect](https://appstoreconnect.apple.com/) → My Apps → **+** → New App.
2. Platforms: iOS.
3. Name: **Mesozoica**.
4. Primary language: English.
5. Bundle ID: `com.desiredewaele.mesozoica`.
6. SKU: e.g. `mesozoica`.
7. User access: full access.

Paste listing copy from [`store_listing.md`](store_listing.md). Set:

- Privacy policy URL: `https://learnfromdata.ai/mesozoica/privacy`
- Support URL: `https://learnfromdata.ai/mesozoica`
- Marketing URL: `https://learnfromdata.ai/mesozoica`
- Category: Games → Simulation or Adventure (pick one primary, Role Playing as secondary if needed)
- Age rating questionnaire (13+ expected because of user accounts and location)
- App Encryption: **ITSAppUsesNonExemptEncryption** is already `false` in `Info.plist` (HTTPS only)

---

## 3. Capabilities that reviewers will ask about

| Capability | Why Mesozoica has it | What to write in review notes |
| --- | --- | --- |
| Location When In Use | Map, nearby sites | Required for the core loop |
| Location Always | Optional background exploring + in-range site documentation | User opts in from Settings; a disclosure dialog is shown first |
| HealthKit | Walking distance / walk XP | Read distance only; not used for clinical advice |
| Sign in with Apple | Required because Google sign-in is offered | Keep the Apple button on the auth screen |
| Push notifications | Site/social/system alerts | User can refuse the system prompt |

App Review notes should include a demo account (email + password) and a short explanation of background location and HealthKit.

---

## 4. Archive and upload

1. Confirm `flutter/.dart_defines.json` has the Mapbox `pk.*` token. `./run.sh` writes it to `ios/Flutter/MapboxSecrets.xcconfig`.
2. From `flutter/`:

```bash
flutter build ipa --release --dart-define-from-file=.dart_defines.json
```

Or open `flutter/ios/Runner.xcworkspace` in Xcode → Product → Archive → Distribute App → App Store Connect.

3. In App Store Connect, attach the build to a version, add screenshots from `marketing/app-store/`, and submit for review.

### Signing problems

- **"No signing certificate iOS Distribution found"**: create an Apple Distribution certificate, or let Xcode manage signing with a team Admin/Account Holder.
- **"No profiles for 'com.desiredewaele.mesozoica'"**: enable Automatically manage signing, or create an App Store provisioning profile for this App ID.
- **HealthKit / Sign in with Apple missing from the profile**: re-check the App ID capabilities, then refresh profiles in Xcode → Settings → Accounts.

---

## 5. Screenshots

Apple currently requires 6.9" iPhone screenshots (and iPad if you support iPad, which this project does). Capture sources on a 6.9" simulator, then:

```bash
python3 scripts/generate_app_store_screenshots.py
```

See [`store-launch.md`](store-launch.md) for the shot list.
