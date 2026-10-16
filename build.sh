#!/bin/bash
set -e

export DEVELOPER_DIR="/Library/Developer/CommandLineTools"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

BUILD_DIR="$DIR/build"
APP_NAME="WordBlocker"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
MACOS_DIR="$APP_BUNDLE/Contents/MacOS"
RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"

echo "=== Building $APP_NAME ==="

mkdir -p "$BUILD_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Ensure VFS overlay exists to avoid CLT duplicate modulemap conflict
if [ ! -f "$DIR/vfs.yaml" ]; then
    cat << 'EOF' > "$DIR/vfs.yaml"
{
  "version": 0,
  "case-sensitive": "false",
  "roots": [
    {
      "type": "directory",
      "name": "/Library/Developer/CommandLineTools/usr/include/swift",
      "contents": [
        {
          "type": "file",
          "name": "module.modulemap",
          "external-contents": "/dev/null"
        }
      ]
    }
  ]
}
EOF
fi

SOURCES=(
    "Sources/Storage/WordStore.swift"
    "Sources/Core/PermissionsManager.swift"
    "Sources/Core/ObfuscationNormalizer.swift"
    "Sources/Core/FuzzyMatcher.swift"
    "Sources/Core/WordBufferEngine.swift"
    "Sources/Core/ActionDispatcher.swift"
    "Sources/Core/EventTapManager.swift"
    "Sources/Core/BrowserMonitor.swift"
    "Sources/Core/CinemaModeManager.swift"
    "Sources/UI/InterventionModalController.swift"
    "Sources/UI/PopupNoteController.swift"
    "Sources/UI/SettingsWindowController.swift"
    "Sources/UI/MenuBarController.swift"
    "Sources/Main.swift"
)

echo "Compiling Swift sources..."
SWIFTC_BIN="/Library/Developer/CommandLineTools/usr/bin/swiftc"
if [ ! -f "$SWIFTC_BIN" ]; then SWIFTC_BIN="swiftc"; fi

"$SWIFTC_BIN" \
    -O \
    -sdk "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk" \
    -target arm64-apple-macos14.0 \
    -Xcc -ivfsoverlay -Xcc "$DIR/vfs.yaml" \
    "${SOURCES[@]}" \
    -o "$MACOS_DIR/$APP_NAME"

echo "Assembling $APP_NAME.app bundle..."
cp "Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

echo "Signing app bundle with stable designated requirement..."
codesign --force --deep -s - -r="designated => identifier \"com.wordblocker.app\"" "$APP_BUNDLE"

# Mirror to project root for easy double-clicking in Finder
rm -rf "$DIR/$APP_NAME.app"
cp -R "$APP_BUNDLE" "$DIR/$APP_NAME.app"

# Register with macOS LaunchServices
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f "$DIR/$APP_NAME.app" 2>/dev/null || true

echo "✅ Build complete!"
echo "   • Bundle: $DIR/$APP_NAME.app (ready to double-click in Finder)"
echo "   • Build folder: $APP_BUNDLE"

if [ "$1" == "run" ]; then
    echo "Launching $APP_NAME..."
    open "$DIR/$APP_NAME.app"
fi
