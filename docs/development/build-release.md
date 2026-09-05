# Build and release

## Requirements

macOS, Swift, and Xcode 15 or later. The deployment target is macOS 13. Peck uses AppKit with no third-party dependencies. Run commands from the repository root.

```bash
xcodebuild -project Peck.xcodeproj -scheme Peck -configuration Debug -destination 'platform=macOS' build
xcodebuild -project Peck.xcodeproj -scheme Peck -destination 'platform=macOS' test
xcodebuild -project Peck.xcodeproj -scheme Peck -configuration Release -destination 'platform=macOS' build
```

The host-less XCTest bundle exercises scheduling, filtering decisions, profile validation, hotkey dispatch, calibration, and other logic without granting the app Accessibility. Actual event receipt needs separate manual verification.

## Command Line Tools fallback

```bash
./Scripts/build-no-xcode.sh
```

This produces an ad-hoc-signed `build/Peck.app` using `swiftc`, targeting the host architecture. `PECK_APP_PATH` can select an output location. The version comes from the Xcode project. The script retries signing when file-provider metadata interferes and may fall back to a temporary output directory; read its reported path.

## Package a built app

The packaging script copies the input bundle and refuses to replace an existing output archive. `ditto` preserves bundle structure and signing data. These commands package locally; they do not publish a GitHub release.

```bash
./Scripts/package-release.sh build/Peck.app dist
# dist/Peck-adhoc.zip, not notarized
```

Optional Developer ID signing requires the certificate and private key in the macOS keychain. Signing uses hardened runtime and a secure timestamp:

```bash
PECK_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
  ./Scripts/package-release.sh build/Peck.app dist
# dist/Peck-developer-id.zip, not notarized
```

For notarization, store credentials with Apple's `xcrun notarytool store-credentials` flow. Keep secrets out of the repository. Explicit `--notarize` submits the app to Apple using the named keychain profile:

```bash
PECK_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
PECK_NOTARY_PROFILE='peck-notary' \
  ./Scripts/package-release.sh build/Peck.app dist --notarize
# dist/Peck-notarized.zip, after successful verification
```

The script waits for notarization, staples and validates the ticket, verifies signing, and performs Gatekeeper assessment. Any failed step stops packaging. The credentialed signing/notarization path has not been exercised for the current release; the distributed artifact remains explicitly ad-hoc.

## Publication

CI builds Debug and Release, runs tests, checks the fallback build, and validates packaging-script syntax. The release workflow packages and publishes on configured version-tag or explicit release triggers. Failed release creation does not overwrite existing assets. Before publishing, verify the version/build number, architecture slices, extracted signature, and archive checksum, and review [verification limits](../verification.md).
