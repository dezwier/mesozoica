# Google Play Store: Android release (Mesozoica)

Guide to building and publishing the Mesozoica Android app. Application ID: **`com.mesozoica.mesozoica`**.

This ID is already registered in Firebase (`flutter/android/app/google-services.json`). Do not change it after the first Play upload.

## Prerequisites

- [Google Play Developer account](https://play.google.com/console) ($25 one-time).
- A Mapbox public token in `flutter/.dart_defines.json` (see [`../flutter/README.md`](../flutter/README.md)).
- No physical Android device is required for the first upload: use an emulator and the **internal testing** track.

---

## 1. Application ID

- **Application ID / namespace**: `com.mesozoica.mesozoica`
- Configured in `flutter/android/app/build.gradle.kts`
- iOS uses a different bundle ID (`com.desiredewaele.mesozoica`). That is expected; do not try to force them to match after Firebase is already wired.

---

## 2. Release signing (upload key)

Play requires a signed **Android App Bundle (AAB)**. You manage an **upload keystore**; Play App Signing holds the final app signing key.

### 2.1 Create the upload keystore (one-time)

```bash
cd flutter/android
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Keep `upload-keystore.jks` safe. It is gitignored. Losing it after Play App Signing is enrolled is recoverable; losing it *before* the first upload is not.

### 2.2 Configure Gradle

```bash
cd flutter/android
cp key.properties.example key.properties
```

Replace the password placeholders. Do not commit `key.properties`.

---

## 3. Google Sign-In SHA-1

Debug and release should use an Android OAuth client whose package name is `com.mesozoica.mesozoica` and whose SHA-1 matches the keystore you ship.

```bash
keytool -list -v -keystore flutter/android/upload-keystore.jks -alias upload
```

In [Google Cloud Console](https://console.cloud.google.com/) → APIs & Services → Credentials:

1. Create or edit an **Android** OAuth client.
2. Package name: `com.mesozoica.mesozoica`.
3. Paste the **upload keystore SHA-1**.
4. After Play App Signing is on, also add the **App signing key certificate SHA-1** from Play Console → App integrity (Google Sign-In on Play-installed builds uses that SHA-1).

The existing Web client in Firebase is enough for `id_token` exchange; you do not need a new `google-services.json` just to add a SHA-1.

---

## 4. Build the App Bundle

```bash
cd flutter
./build_play
```

Output: `flutter/build/app/outputs/bundle/release/app-release.aab`.

`./build_play` reads `flutter/.dart_defines.json` so the Mapbox public token is compiled into the release.

---

## 5. Play Console: first-time setup

1. Create the app named **Mesozoica**, default language English.
2. Accept **Play App Signing** on the first AAB upload.
3. Start on **Internal testing**, then closed testing, then production.

Store listing copy lives in [`store_listing.md`](store_listing.md). Policy URLs:

| Field | URL |
| --- | --- |
| Privacy policy | `https://learnfromdata.ai/mesozoica/privacy` |
| Delete account URL | `https://learnfromdata.ai/mesozoica/delete-account` |
| Delete data URL | `https://learnfromdata.ai/mesozoica/delete-data` |

Complete **Policy → App content**:

- Data safety (account, location, health/fitness walking distance, photos, user content).
- Content rating questionnaire.
- Target audience (13+).
- News app: no.
- COVID: no.
- Financial features: no.
- Ads: no.
- **User-generated content**: yes (profiles, photos, social). Point to the in-app report/block flows you have, or add them before production if review asks.
- **Background location**: restricted permission. You must:
  1. Keep the in-app disclosure (Settings → Background location).
  2. Upload a short video showing the prominent disclosure, the system Always-location prompt, and the ongoing "Exploring fossil sites" notification.
  3. Explain that background location is optional and used only for nearby site discovery, in-range documentation, and walk XP.

Health Connect / walking distance: declare Health data in Data safety if the Android build can read Health Connect.

---

## 6. Testing without a physical device

```bash
cd flutter && ./run.sh -d <emulator_id>
```

After the AAB is on internal testing, install from the Play testing link on an emulator image that includes Play Store.
