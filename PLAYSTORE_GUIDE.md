# Stack Tower - Play Store Ready Guide & Documentation

## 🚀 App Status: BUILD & PUBLISH READY

- **Application ID / Package Name:** `com.stacktower.casual.game`
- **Current Version:** `1.0.3+4` (Build 4 - Production Ready)
- **Min SDK:** 23 (Android 6.0+)
- **Target SDK:** 34 / 35 (Latest Android)
- **Release Bundle (.aab):** `build/app/outputs/bundle/release/app-release.aab`
- **Keystore Location:** `android/upload-keystore.jks` & `android/app/upload-keystore.jks`
- **Keystore Config:** `android/key.properties`

---

## 🔑 Keystore Information (CRITICAL - KEEP SAFE)

A production release keystore has already been generated and configured:
```properties
storePassword=StackTowerKey2026!
keyPassword=StackTowerKey2026!
keyAlias=upload
storeFile=../upload-keystore.jks
```
> ⚠️ **IMPORTANT:** Keep `android/upload-keystore.jks` and `android/key.properties` safe and backed up in Google Drive or offline storage. Never share them publicly. If lost, Google will not let you update the app on Play Store.

---

## 🎨 Prepared Store Assets (In `assets/` folder)

All Google Play Store graphic assets are pre-formatted to exact Play Console requirements:

1. **High-Res App Icon (512x512 PNG):**
   - File: `assets/playstore_icon_512.png` (512x512 32-bit PNG)
2. **Feature Graphic (1024x500 JPG):**
   - File: `assets/feature_graphic.jpg` (1024x500 px)
3. **Phone Screenshots:**
   - Screenshot 1: `assets/screenshots/screenshot_1.jpg` (Vertical 9:16)
   - Screenshot 2: `assets/screenshots/screenshot_2.jpg` (Vertical 9:16)
4. **Privacy Policy:**
   - File: `privacy_policy.html` (Styled with `support@stacktower.com`)

---

## 📱 Configured Real AdMob IDs

Your real AdMob IDs have been integrated into the project:
- **AdMob App ID:** `ca-app-pub-6236208130146050~6212995950` (in `android/app/src/main/AndroidManifest.xml`)
- **Banner Ad Unit ID:** `ca-app-pub-6236208130146050/4185598419` (in `lib/ads.dart`)
- **Interstitial Ad Unit ID:** `ca-app-pub-6236208130146050/1176291697` (in `lib/ads.dart`)

> 💡 **Notice:** Debug mode (`flutter run`) automatically uses Google's official Test Ads so your account is never flagged for self-clicks. Release builds (`flutter build appbundle --release`) use your real IDs above.

---

## 🌐 How to Host Privacy Policy for Free (GitHub Pages)

Google Play requires a public HTTPS URL:
1. Create a GitHub repo (e.g. `stack-tower-policy`).
2. Upload `privacy_policy.html` as `index.html`.
3. Go to **Settings -> Pages -> Deploy from branch (main/root)**.
4. Your link will be: `https://<your-username>.github.io/stack-tower-policy/`.
5. Paste this URL into Google Play Console's Privacy Policy field.

---

## 📝 Play Store Listing Details

### App Title
`Stack Tower - Tap & Build`

### Short Description (Max 80 chars)
`Tap at the perfect moment, stack neon blocks, and build the tallest tower!`

### Full Description (Up to 4000 chars)
```
Stack Tower is a sleek, addictive tap-timing arcade game designed for quick, satisfying fun!

How to Play:
- Tap the screen at the exact moment to drop the moving block onto the tower.
- Match the block underneath perfectly to maintain size.
- Chain PERFECT drops to trigger expanding blocks and boost your tower!
- Avoid miss-timed taps: any overhang gets sliced off. Miss completely, and it's GAME OVER!

Features:
- Vibrant neon visuals and dynamic color transitions
- Smooth, responsive 60+ FPS physics
- Tactile haptic feedback and click effects
- High score tracking stored locally on your device
- One-tap gameplay easy to learn, challenging to master!

How high can you stack? Challenge yourself and beat your personal best today!
```

---

## 📋 Google Play Console Questionnaire Answers

When filling out the **App Content** questionnaires in Play Console:

| Questionnaire | Answer / Option to Select |
| :--- | :--- |
| **Privacy Policy** | Your hosted GitHub Pages link |
| **Ads** | Select **"Yes, my app contains ads"** |
| **App Access** | Select **"All functionality is available without special access"** |
| **Content Rating** | Category: **Game** -> Violence: **No** -> Age rating will be **Everyone (3+) / PEGI 3** |
| **Target Audience & Content** | Target age: **13 and older** (Check 13-15, 16-17, 18+). Under 13: **No**. This avoids strict Families Policy complications. |
| **News Apps / COVID-19 / Financial** | Select **No** for all |
| **Data Safety** | Data Collected: **Device or other IDs (Advertising ID)** collected by Google AdMob. Purpose: **Advertising or marketing, Analytics**. Is data encrypted in transit? **Yes**. Can user request data deletion? **Yes (via Google ad settings)**. |
| **Government Apps** | Select **No** |

---

## 🧪 Closed Testing (New Developer Accounts Rule)

If you have a personal Google Play Developer account created after Nov 2023:
1. In Play Console, go to **Testing -> Closed testing**.
2. Create a track (e.g., "Closed Alpha").
3. Upload `build/app/outputs/bundle/release/app-release.aab`.
4. Add 20 email addresses of testers (friends, family, or testing groups).
5. Send them the opt-in link.
6. Once 20 testers have opted in for 14 continuous days, the "Apply for Production" button will be enabled!
