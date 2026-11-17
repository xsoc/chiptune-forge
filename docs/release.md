# Releasing to the app stores

What is ready in this repository, and the steps that need a store account.
The stores need accounts that only the project's owner can open, so the
uploads themselves are manual.

## What CI makes

A version tag (`git tag v1.0.0 && git push --tags`) runs the release:

| Job | Output | Notes |
|---|---|---|
| Export | Web, Linux, Windows, macOS builds, an Android APK | Signed with the release key when the repository has one (see below), else the debug key. |
| Publish GitHub Release | The builds, attached to a GitHub release | Also deploys the web build to GitHub Pages from `main`. |
| Google Play bundle | `chiptune-forge.aab` | Only with the release key. Uses Godot's Gradle build. |
| Store listing | `store/`: listing text and screenshots | Screenshots at each size below, made by `tools/store_screenshots.sh`. |

The last two also run from the Actions tab ("Run workflow") without a tag.
The tag sets the version everywhere (`tools/stamp_version.sh`): `v1.2.3`
becomes version 1.2.3 and Android version code 10203.

## Listing material

- Text: [store/metadata](../store/metadata), laid out the way fastlane
  expects (`android/en-US`, `ios/en-US`), within each store's length limits.
- Screenshots: `bash tools/store_screenshots.sh` writes
  `store/screenshots/<device>/` for an Android phone (1080 x 1920), an
  Android tablet (1920 x 1200), 6.9" and 6.5" iPhones (1320 x 2868 and
  1284 x 2778), a 13" iPad (2064 x 2752) and desktop (1920 x 1080).
- Icon: `icon.svg`. Export a 512 x 512 PNG for Google Play and a
  1024 x 1024 PNG with no transparency for the App Store.
- Privacy policy: [docs/privacy.md](privacy.md). Use its GitHub URL as the
  privacy policy link.
- Category: Music (or Tools). Price: free. No ads, no in-app purchases.

## Google Play

Needs: a Google Play developer account (one-time fee).

1. Make an upload key, once, and keep it safe (losing it means asking Google
   to reset it):
   `keytool -genkeypair -v -keystore release.keystore -alias chiptuneforge -keyalg RSA -keysize 2048 -validity 10000`
2. Add three repository secrets (Settings, Secrets and variables, Actions):
   `ANDROID_KEYSTORE_BASE64` (`base64 -w0 release.keystore`),
   `ANDROID_KEYSTORE_USER` (the alias) and `ANDROID_KEYSTORE_PASSWORD`.
3. Tag a release. Download the `chiptune-forge-play-bundle` artifact.
4. In the Play Console, create the app with package name
   `org.chiptuneforge.app`, turn on Play App Signing, and upload the bundle
   to internal testing first.
5. Fill in the forms:
   - Data safety: no data collected, no data shared.
   - Content rating (IARC questionnaire): no violence, no user-generated
     content shared between users, no purchases. Expect "Everyone".
   - Target audience: all ages. Ads: none. App access: no login.
6. Paste the listing text, upload the screenshots and icon, and send it for
   review.

The Android build asks for no permissions. Before the first upload, check
that the target API level Godot sets meets Play's current minimum (the Play
Console says so on upload); if not, set `gradle_build/target_sdk` in the
"Android Play" preset.

## Apple App Store

Needs: an Apple Developer Program membership (yearly fee) and a Mac with
Xcode. Godot builds iOS apps through an Xcode project, which needs macOS.

1. In Godot on the Mac, add an iOS export preset: bundle identifier
   `org.chiptuneforge.app`, your team ID, the icons from `icon.svg`, and the
   same include filter as the Android preset in `export_presets.cfg`.
   Turn off any capabilities; the app needs none.
2. Export the Xcode project, open it, set signing to your team, and
   Product, Archive. Upload from the Organizer to App Store Connect.
3. In App Store Connect:
   - App Privacy: "Data Not Collected".
   - Age rating: 4+.
   - Export compliance: the app uses no non-exempt encryption.
   - Paste the text from `store/metadata/ios/en-US` and upload the iPhone
     and iPad screenshots.
4. Test through TestFlight, then submit for review.

The Mac App Store takes the macOS build the same way, after signing and
notarising it with the same membership.

## Other stores

- **itch.io**: no review. Upload the web zip (play in browser) and the
  desktop builds from the GitHub release, or push them with butler.
- **Flathub, Microsoft Store, Steam**: each needs its own account or fee.
  The Linux and Windows builds from the release are the starting point.

## Trademarks

Store reviewers can be strict about console names. The listing names
consoles only to say what the exports work with, and says that the names
belong to their owners and that the app is not affiliated with them. Keep
console names and logos out of the app's name, icon and screenshots' captions.
