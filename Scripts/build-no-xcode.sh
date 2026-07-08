#!/bin/bash
# Insurance policy: builds Peck.app with plain swiftc, no Xcode project needed.
# Requires Xcode Command Line Tools (xcode-select --install).
set -euo pipefail
cd "$(dirname "$0")/.."

DEFAULT_APP="build/Peck.app"

build_app() {
    local app="$1"

    rm -rf "$app"
    mkdir -p "$app/Contents/MacOS"
    mkdir -p "$app/Contents/Resources"

    # App icon (if present in the source tree).
    if [[ -f Peck/AppIcon.icns ]]; then
        cp Peck/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
    fi

    cat > "$app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>Peck</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>dev.homelab.peck</string>
	<key>CFBundleName</key>
	<string>Peck</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.utilities</string>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
</dict>
</plist>
EOF

    # Auto-detect the host architecture so this builds natively on both Apple
    # Silicon (arm64) and Intel (x86_64) without hand-editing the triple.
    local arch
    arch="$(uname -m)"

    swiftc -O \
        -target "${arch}-apple-macosx13.0" \
        -o "$app/Contents/MacOS/Peck" \
        Peck/*.swift

    # If the build tree lives under an iCloud-synced ~/Documents (a "file provider"
    # location), macOS keeps asynchronously re-stamping com.apple.FinderInfo on the
    # freshly built bundle. codesign rejects that as "detritus", and a single clear
    # can lose the race, so clear-and-sign in a short retry loop.
    local attempt
    for attempt in 1 2 3 4 5; do
        xattr -cr "$app" 2>/dev/null || true
        if codesign --force -s - "$app" 2>/dev/null; then
            break
        fi
        if [[ "$attempt" -eq 5 ]]; then
            echo "codesign kept failing under $app (FinderInfo re-stamp race?)" >&2
            return 1
        fi
        sleep 0.4
    done

    xattr -cr "$app" 2>/dev/null || true
    codesign --verify --deep --strict "$app"
}

APP="${PECK_APP_PATH:-$DEFAULT_APP}"

if ! build_app "$APP"; then
    if [[ -n "${PECK_APP_PATH:-}" ]]; then
        echo "Build failed: $APP" >&2
        exit 1
    fi

    rm -rf "$APP"
    APP="${TMPDIR:-/tmp}"
    APP="${APP%/}/Peck.app"
    echo "Could not sign under $DEFAULT_APP; retrying at $APP"
    build_app "$APP"
fi

echo "Built: $APP"
echo "Move it to /Applications, launch it, and grant Accessibility when prompted."
