#!/bin/bash
# Package a built bundle without changing the input. Network submission is opt-in.
set -euo pipefail

usage() {
    echo 'Usage: package-release.sh APP OUTPUT_DIR [--notarize]' >&2
    echo 'Optional: PECK_SIGN_IDENTITY="Developer ID Application: ..."' >&2
    echo 'Notarization also requires PECK_NOTARY_PROFILE (a stored keychain profile).' >&2
    exit 2
}
[[ $# -ge 2 && $# -le 3 ]] || usage
app="$1"
output="$2"
notarize=false
if [[ $# -eq 3 ]]; then
    [[ "$3" == --notarize ]] || usage
    notarize=true
fi
[[ -d "$app/Contents/MacOS" && -f "$app/Contents/Info.plist" ]] || {
    echo 'Input must be a built app bundle.' >&2; exit 1;
}
app="$(cd -- "$app" && pwd)"
identity="${PECK_SIGN_IDENTITY:-}"
profile="${PECK_NOTARY_PROFILE:-}"
if [[ -n "$identity" && "$identity" != 'Developer ID Application: '* ]]; then
    echo 'PECK_SIGN_IDENTITY must name a Developer ID Application identity.' >&2
    exit 1
fi
if $notarize && [[ -z "$identity" || -z "$profile" ]]; then
    echo '--notarize requires PECK_SIGN_IDENTITY and PECK_NOTARY_PROFILE.' >&2
    exit 1
fi
kind=adhoc
[[ -z "$identity" ]] || kind=developer-id
if $notarize; then kind=notarized; fi
mkdir -p -- "$output"
output="$(cd -- "$output" && pwd)"
archive="$output/Peck-$kind.zip"
[[ ! -e "$archive" ]] || { echo "Refusing to replace $archive" >&2; exit 1; }
work="$(mktemp -d "${TMPDIR:-/tmp}/peck-package.XXXXXX")"
trap 'rm -rf "$work"' EXIT
bundle="$work/Peck.app"
ditto "$app" "$bundle"
xattr -cr "$bundle"
if [[ -n "$identity" ]]; then
    codesign --force --options runtime --timestamp --sign "$identity" "$bundle"
else
    codesign --force --options runtime --sign - "$bundle"
fi
codesign --verify --deep --strict "$bundle"
if $notarize; then
    ditto -c -k --keepParent "$bundle" "$work/submission.zip"
    xcrun notarytool submit "$work/submission.zip" --keychain-profile "$profile" --wait
    xcrun stapler staple "$bundle"
    xcrun stapler validate "$bundle"
    codesign --verify --deep --strict "$bundle"
    spctl --assess --type execute --verbose=2 "$bundle"
fi
ditto -c -k --keepParent "$bundle" "$work/Peck.zip"
# Hard-link publication fails atomically if another process claimed the name.
# Stage beside the output so the final link stays on the same filesystem.
staged="$(mktemp "$output/.peck-package.XXXXXX")"
trap 'rm -rf "$work"; rm -f "$staged"' EXIT
cp "$work/Peck.zip" "$staged"
ln "$staged" "$archive"
echo "Packaged ($kind): $archive"
shasum -a 256 "$archive"
