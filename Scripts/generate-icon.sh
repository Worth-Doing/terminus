#!/bin/bash
set -euo pipefail

# Generate .icns from SVG using macOS native tools
# Requires: sips, iconutil (both built into macOS)

SVG_INPUT="Resources/AppIcon.svg"
ICONSET_DIR="Resources/AppIcon.iconset"
ICNS_OUTPUT="Resources/AppIcon.icns"
TMP_PNG="/tmp/terminus_icon_1024.png"

echo "=== Generating Terminus icon ==="

# Step 1: Convert SVG to 1024x1024 PNG
# Try qlmanage first (works with SVG on macOS)
echo "[1/3] Converting SVG to PNG..."

# Use Python with CoreGraphics to render SVG to PNG
python3 << 'PYEOF'
import subprocess, sys, os

svg_path = "Resources/AppIcon.svg"
tmp_png = "/tmp/terminus_icon_1024.png"

# Method: use sips via a temporary PDF, or use qlmanage
# Try qlmanage first (built into macOS, handles SVG)
try:
    subprocess.run(
        ["qlmanage", "-t", "-s", "1024", "-o", "/tmp", svg_path],
        capture_output=True, check=True
    )
    # qlmanage outputs to /tmp/AppIcon.svg.png
    ql_output = f"/tmp/{os.path.basename(svg_path)}.png"
    if os.path.exists(ql_output):
        os.rename(ql_output, tmp_png)
        print(f"  Generated via qlmanage: {tmp_png}")
        sys.exit(0)
except Exception:
    pass

# Fallback: use rsvg-convert if available
try:
    subprocess.run(
        ["rsvg-convert", "-w", "1024", "-h", "1024", svg_path, "-o", tmp_png],
        capture_output=True, check=True
    )
    print(f"  Generated via rsvg-convert: {tmp_png}")
    sys.exit(0)
except FileNotFoundError:
    pass

# Fallback: use Swift to render SVG
swift_code = '''
import AppKit
let svgPath = "Resources/AppIcon.svg"
let outputPath = "/tmp/terminus_icon_1024.png"
guard let svgData = FileManager.default.contents(atPath: svgPath),
      let image = NSImage(data: svgData) else {
    print("Failed to load SVG")
    exit(1)
}
let size = NSSize(width: 1024, height: 1024)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                            isPlanar: false, colorSpaceName: .deviceRGB,
                            bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
image.draw(in: NSRect(origin: .zero, size: size))
NSGraphicsContext.restoreGraphicsState()
guard let pngData = rep.representation(using: .png, properties: [:]) else {
    print("Failed to create PNG")
    exit(1)
}
try! pngData.write(to: URL(fileURLWithPath: outputPath))
print("Generated via Swift: " + outputPath)
'''
# Write and run swift script
with open("/tmp/render_svg.swift", "w") as f:
    f.write(swift_code)
try:
    subprocess.run(["swift", "/tmp/render_svg.swift"], check=True)
    sys.exit(0)
except Exception as e:
    print(f"  Swift render failed: {e}")

print("ERROR: Could not convert SVG to PNG. Install rsvg-convert: brew install librsvg")
sys.exit(1)
PYEOF

if [ ! -f "$TMP_PNG" ]; then
    echo "ERROR: PNG generation failed"
    exit 1
fi

# Step 2: Create iconset with all required sizes
echo "[2/3] Creating iconset..."
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

# Required sizes for macOS .icns
declare -a SIZES=(16 32 64 128 256 512 1024)

for size in "${SIZES[@]}"; do
    sips -z "$size" "$size" "$TMP_PNG" --out "$ICONSET_DIR/icon_${size}x${size}.png" > /dev/null 2>&1

    # @2x versions (half the name, double the pixels)
    half=$((size / 2))
    if [ "$half" -ge 16 ] && [ "$size" -le 512 ]; then
        cp "$ICONSET_DIR/icon_${size}x${size}.png" "$ICONSET_DIR/icon_${half}x${half}@2x.png"
    fi
done

# Rename 1024 to 512@2x (required by iconutil)
if [ -f "$ICONSET_DIR/icon_1024x1024.png" ]; then
    cp "$ICONSET_DIR/icon_1024x1024.png" "$ICONSET_DIR/icon_512x512@2x.png"
fi

# Clean up non-standard sizes
rm -f "$ICONSET_DIR/icon_64x64.png"
rm -f "$ICONSET_DIR/icon_1024x1024.png"

echo "  Sizes generated:"
ls -1 "$ICONSET_DIR/" | sed 's/^/    /'

# Step 3: Convert to .icns
echo "[3/3] Building .icns..."
iconutil -c icns "$ICONSET_DIR" -o "$ICNS_OUTPUT"

# Cleanup
rm -rf "$ICONSET_DIR"
rm -f "$TMP_PNG"

ICON_SIZE=$(du -sh "$ICNS_OUTPUT" | cut -f1)
echo ""
echo "=== Icon generated ==="
echo "  Output: $ICNS_OUTPUT ($ICON_SIZE)"
