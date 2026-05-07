#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
DIST_DIR="$ROOT_DIR/dist"
BUILD_DIR="$ROOT_DIR/.build/arm64-apple-macosx/release"
PRODUCT_NAME="Zipic"
APP_NAME="Zipic"
ICON_NAME="AppIcon"
APP_DIR="$DIST_DIR/$APP_NAME.app"
EXECUTABLE_PATH="$APP_DIR/Contents/MacOS/$PRODUCT_NAME"
FRAMEWORKS_DIR="$APP_DIR/Contents/Frameworks"
RESOURCES_DIR="$APP_DIR/Contents/Resources"
INFO_PLIST="$APP_DIR/Contents/Info.plist"
ZIP_PATH="$DIST_DIR/$APP_NAME-arm64.zip"
SOURCE_ICON_PATH="$ROOT_DIR/Resources/$ICON_NAME.icns"

cd "$ROOT_DIR"

"$ROOT_DIR/scripts/generate_icon.sh"

rm -rf "$DIST_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$RESOURCES_DIR" "$FRAMEWORKS_DIR"

swift build -c release --arch arm64

cp "$BUILD_DIR/$PRODUCT_NAME" "$EXECUTABLE_PATH"
cp "$SOURCE_ICON_PATH" "$RESOURCES_DIR/$ICON_NAME.icns"
chmod +x "$EXECUTABLE_PATH"

cat > "$INFO_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>
    <string>$PRODUCT_NAME</string>
    <key>CFBundleIconFile</key>
    <string>$ICON_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>tech.xinxiao.zipic</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.graphics-design</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

install_name_tool -add_rpath "@executable_path/../Frameworks" "$EXECUTABLE_PATH" 2>/dev/null || true

xcrun swift-stdlib-tool \
  --copy \
  --scan-executable "$EXECUTABLE_PATH" \
  --destination "$FRAMEWORKS_DIR" \
  --platform macosx

xattr -cr "$APP_DIR"
codesign --force --deep --sign - "$APP_DIR" >/dev/null

ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"

echo "App: $APP_DIR"
echo "Zip: $ZIP_PATH"
