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
| Location Always | Optional background exploring + in-range site documentation | User opts in from Settings → App → Background location; a disclosure dialog is shown first |
| HealthKit | Walking distance / walk XP | Read distance only; not used for clinical advice |
| Sign in with Apple | Required because Google sign-in is offered | Official Sign in with Apple button on the auth screen |
| Push notifications | Site/social/system alerts | User can refuse the system prompt |

App Review notes must include a demo account (email + password), the background-location steps below, and a physical-iPhone screen recording in **App Review Information → Notes**.

### Review notes to paste

```
Background location
Mesozoica uses persistent location for two gameplay features:
1. Optional Background location (Profile → Settings → App → Background location). Default is off. After an in-app disclosure, the app requests Always so nearby site discovery and walk XP continue while the device is locked.
2. In-range site documentation. While the player is standing on an identified undocumented site, documentation continues if they lock the phone or switch apps. The site card says "Documenting — continues while locked".

Path on device: Profile → Settings → App → Background location → Continue → grant Always. iOS then shows the blue background-location indicator.

The attached recording is from an iPhone. Wi-Fi iPads have no GPS, so the walking loop is not demonstrable on an iPad Air review device.

HealthKit
Walking distance / walk XP only. Mesozoica does not write health records and does not give clinical advice.

Account deletion
Signed-in users can delete the account in-app with no extra steps: Profile → Settings → Delete account (App tab), then confirm. A password is not required (including Sign in with Apple accounts).

Sign in with Apple
The auth screen uses the official Sign in with Apple button widget. It does not load third-party Apple logo artwork.
```

### Physical iPhone recording checklist (Guideline 2.5.4)

Record on a physical iPhone, not iPad and not Simulator:

1. Profile → Settings → App → **Background location** → Continue → grant **Always**.
2. Press Home / lock the phone. Capture the iOS blue **background location indicator**.
3. Optional: walk into a discovered undocumented site, lock the phone, and show documentation still advancing.
4. Upload the clip in App Store Connect → App Review Information → **Notes**, and attach it when replying to the review thread.

### Reply to the 1.0 (5) rejection

After uploading **1.0 (6)**, reply on the App Review thread:

```
Thank you for the review.

1. Sign in with Apple: the button now uses the official Sign in with Apple control. Third-party Apple logo artwork has been removed.

2. Background location: Mesozoica uses persistent location for optional Background location (Profile → Settings → App → Background location) and for in-range site documentation while the device is locked. A physical-iPhone screen recording is attached in App Review Information → Notes. Wi-Fi iPads have no GPS, so this loop is not visible on an iPad Air.

3. Account deletion: signed-in users can delete the account in-app from Profile → Settings → Delete account on the App tab. No password, extra account, or support contact is required, including for Sign in with Apple.
```

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
