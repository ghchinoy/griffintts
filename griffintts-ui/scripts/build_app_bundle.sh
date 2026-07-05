#!/bin/bash
# Automated macOS App Bundle Packaging Script for GriffinTTS
#
# Generates GriffinTTS.app bundle, compiles release assets, creates
# high-resolution .icns file, and writes standard Info.plist.
#
# Usage:
#     ./tools/griffintts-ui/scripts/build_app_bundle.sh

set -e

PROJECT_ROOT="/Users/ghchinoy/projects/jibo"
APP_NAME="GriffinTTS"
BUNDLE_DIR="${PROJECT_ROOT}/tools/bin/${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MCOS_DIR="${CONTENTS_DIR}/MacOS"
RES_DIR="${CONTENTS_DIR}/Resources"

echo "=== Starting GriffinTTS App Bundle Build ==="

# 1. Compile production Release build of Swift SwiftUI app
echo "Compiling optimized Swift SwiftUI production build..."
swift build --package-path "${PROJECT_ROOT}/tools/griffintts-ui" -c release

# 2. Create standard App Bundle directory structures
echo "Structuring App Bundle directory layout..."
mkdir -p "${MCOS_DIR}"
mkdir -p "${RES_DIR}"

# 3. Copy compiled Swift binary into MacOS/
echo "Copying executable..."
cp "${PROJECT_ROOT}/tools/griffintts-ui/.build/release/griffintts-ui" "${MCOS_DIR}/griffintts-ui"
chmod +x "${MCOS_DIR}/griffintts-ui"

# 4. Write standard, valid Info.plist
echo "Writing Info.plist..."
cat << 'EOF' > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.9.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>griffintts-ui</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.jibo.griffintts-ui</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>GriffinTTS</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

# 5. Create high-resolution .icns file from generated PNG
MASTER_PNG=$(ls "${PROJECT_ROOT}/tools/griffintts-ui/Resources"/*.png | head -n 1 || true)

if [ -n "${MASTER_PNG}" ] && [ -f "${MASTER_PNG}" ]; then
    echo "Master PNG icon found: ${MASTER_PNG}"
    ICONSET_DIR="/tmp/${APP_NAME}.iconset"
    mkdir -p "${ICONSET_DIR}"
    
    echo "Resizing and generating standard Apple iconset resolutions..."
    # Generate standard resolutions using macOS built-in sips tool
    sips -z 16 16     "${MASTER_PNG}" --out "${ICONSET_DIR}/icon_16x16.png" >/dev/null
    sips -z 32 32     "${MASTER_PNG}" --out "${ICONSET_DIR}/icon_16x16@2x.png" >/dev/null
    sips -z 32 32     "${MASTER_PNG}" --out "${ICONSET_DIR}/icon_32x32.png" >/dev/null
    sips -z 64 64     "${MASTER_PNG}" --out "${ICONSET_DIR}/icon_32x32@2x.png" >/dev/null
    sips -z 128 128   "${MASTER_PNG}" --out "${ICONSET_DIR}/icon_128x128.png" >/dev/null
    sips -z 256 256   "${MASTER_PNG}" --out "${ICONSET_DIR}/icon_128x128@2x.png" >/dev/null
    sips -z 256 256   "${MASTER_PNG}" --out "${ICONSET_DIR}/icon_256x256.png" >/dev/null
    sips -z 512 512   "${MASTER_PNG}" --out "${ICONSET_DIR}/icon_256x256@2x.png" >/dev/null
    sips -z 512 512   "${MASTER_PNG}" --out "${ICONSET_DIR}/icon_512x512.png" >/dev/null
    sips -z 1024 1024 "${MASTER_PNG}" --out "${ICONSET_DIR}/icon_512x512@2x.png" >/dev/null
    
    echo "Compiling .icns file using iconutil..."
    iconutil -c icns "${ICONSET_DIR}" -o "${RES_DIR}/AppIcon.icns"
    
    # Clean up temp iconset
    rm -rf "${ICONSET_DIR}"
    echo "AppIcon.icns successfully compiled and bundled."
else
    echo "Warning: No master PNG found. App bundle will build without custom icon."
fi

echo "=== App Bundle Build Succeeded: ${BUNDLE_DIR} ==="
