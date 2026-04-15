#!/bin/bash
set -euo pipefail

APP_NAME="Terminus"
VERSION="0.3.0"
BUILD_DIR=".build/release"
BUNDLE_DIR="$BUILD_DIR/$APP_NAME.app"
BUNDLE_ID="com.terminus.app"
DMG_PATH="$BUILD_DIR/$APP_NAME-$VERSION.dmg"

# Signing identity
SIGNING_IDENTITY="Developer ID Application: Simon-Pierre Boucher (3YM54G49SN)"
TEAM_ID="3YM54G49SN"

# Notarization credentials
# Store password in keychain first:
#   xcrun notarytool store-credentials "terminus-notarize" \
#     --apple-id "spbou4@icloud.com" \
#     --team-id "3YM54G49SN" \
#     --password "YOUR_APP_SPECIFIC_PASSWORD"
APPLE_ID="spbou4@icloud.com"
KEYCHAIN_PROFILE="terminus-notarize"

# ──────────────────────────────────────────────────
# Parse arguments
# ──────────────────────────────────────────────────
DO_SIGN=false
DO_NOTARIZE=false

for arg in "$@"; do
    case $arg in
        --sign) DO_SIGN=true ;;
        --notarize) DO_SIGN=true; DO_NOTARIZE=true ;;
        --help)
            echo "Usage: $0 [--sign] [--notarize]"
            echo ""
            echo "  --sign       Code-sign the app bundle"
            echo "  --notarize   Sign + notarize with Apple (requires internet)"
            echo ""
            echo "Without flags: builds an unsigned app bundle for development."
            exit 0
            ;;
    esac
done

echo "=== Building $APP_NAME v$VERSION ==="
echo ""

# ──────────────────────────────────────────────────
# Step 1: Build
# ──────────────────────────────────────────────────
rm -rf "$BUNDLE_DIR"

echo "[1/5] Compiling in release mode..."
swift build -c release 2>&1 | tail -3

# ──────────────────────────────────────────────────
# Step 2: Create bundle
# ──────────────────────────────────────────────────
echo "[2/5] Creating app bundle..."
mkdir -p "$BUNDLE_DIR/Contents/MacOS"
mkdir -p "$BUNDLE_DIR/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$BUNDLE_DIR/Contents/MacOS/"
cp Resources/Info.plist "$BUNDLE_DIR/Contents/"

if [ -f Resources/AppIcon.icns ]; then
    cp Resources/AppIcon.icns "$BUNDLE_DIR/Contents/Resources/"
fi

echo "APPL????" > "$BUNDLE_DIR/Contents/PkgInfo"

BINARY_SIZE=$(du -sh "$BUNDLE_DIR/Contents/MacOS/$APP_NAME" | cut -f1)
echo "      Binary size: $BINARY_SIZE"

# ──────────────────────────────────────────────────
# Step 3: Entitlements
# ──────────────────────────────────────────────────
ENTITLEMENTS_FILE="$BUILD_DIR/Terminus.entitlements"
cat > "$ENTITLEMENTS_FILE" << 'ENTITLEMENTS'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
</dict>
</plist>
ENTITLEMENTS

# ──────────────────────────────────────────────────
# Step 4: Code signing
# ──────────────────────────────────────────────────
if [ "$DO_SIGN" = true ]; then
    echo "[3/5] Code signing..."
    codesign --force --deep --options runtime \
        --entitlements "$ENTITLEMENTS_FILE" \
        --sign "$SIGNING_IDENTITY" \
        --timestamp \
        "$BUNDLE_DIR"

    echo "      Verifying signature..."
    codesign --verify --deep --strict "$BUNDLE_DIR"
    echo "      Signature valid."
else
    echo "[3/5] Skipping code signing (use --sign to enable)"
fi

# ──────────────────────────────────────────────────
# Step 5: Notarization
# ──────────────────────────────────────────────────
if [ "$DO_NOTARIZE" = true ]; then
    echo "[4/5] Creating ZIP for notarization..."

    # Create a ZIP archive for notarization (Apple accepts .zip)
    ZIP_PATH="$BUILD_DIR/$APP_NAME-$VERSION.zip"
    rm -f "$ZIP_PATH"
    ditto -c -k --keepParent "$BUNDLE_DIR" "$ZIP_PATH"
    ZIP_SIZE=$(du -sh "$ZIP_PATH" | cut -f1)
    echo "      ZIP: $ZIP_PATH ($ZIP_SIZE)"

    echo "[5/5] Submitting for notarization..."
    xcrun notarytool submit "$ZIP_PATH" \
        --keychain-profile "$KEYCHAIN_PROFILE" \
        --wait

    echo "      Stapling notarization ticket to app bundle..."
    xcrun stapler staple "$BUNDLE_DIR"

    # Now create the final DMG with the stapled app
    echo "      Creating distributable DMG..."
    rm -f "$DMG_PATH"
    ditto -c -k --keepParent "$BUNDLE_DIR" "$DMG_PATH.zip" 2>/dev/null || true

    # Try hdiutil, fall back to keeping the ZIP
    if hdiutil create -volname "$APP_NAME" \
        -srcfolder "$BUNDLE_DIR" \
        -ov -format UDZO \
        "$DMG_PATH" 2>/dev/null; then
        codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$DMG_PATH"
        xcrun stapler staple "$DMG_PATH" 2>/dev/null || true
        DMG_SIZE=$(du -sh "$DMG_PATH" | cut -f1)
        echo ""
        echo "=== Build + Notarize complete ==="
        echo ""
        echo "  DMG: $DMG_PATH ($DMG_SIZE)"
    else
        echo ""
        echo "=== Build + Notarize complete ==="
        echo ""
        echo "  ZIP: $ZIP_PATH ($ZIP_SIZE)"
        echo "  (DMG creation skipped due to macOS permissions)"
    fi
    echo "  App: $BUNDLE_DIR (stapled)"
    echo ""
else
    echo "[4/5] Skipping notarization (use --notarize to enable)"
    echo ""
    echo "=== Build complete ==="
    echo ""
    echo "  App bundle: $BUNDLE_DIR"
    echo "  To launch:  open $BUNDLE_DIR"
    echo "  To install: cp -r $BUNDLE_DIR /Applications/"
    echo ""
fi
