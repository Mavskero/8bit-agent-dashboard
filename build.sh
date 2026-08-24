#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$PROJECT_DIR/build/HermesDashboard.app"
MODULE_CACHE="$PROJECT_DIR/build/ModuleCache.noindex"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
mkdir -p "$MODULE_CACHE"

SWIFT_MODULECACHE_PATH="$MODULE_CACHE" swiftc -O -module-cache-path "$MODULE_CACHE" \
  -framework Cocoa \
  -framework ImageIO \
  -framework UniformTypeIdentifiers \
  "$PROJECT_DIR"/Sources/HermesDashboard/*.swift \
  -o "$APP_DIR/Contents/MacOS/HermesDashboard"

cp "$PROJECT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$PROJECT_DIR/PkgInfo" "$APP_DIR/Contents/PkgInfo"

codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true
echo "Built $APP_DIR"
