#!/usr/bin/env bash
set -euo pipefail

APP_NAME="CoffitivityLocal"
BUILD_DIR=".build/release"
APP_BUNDLE="$APP_NAME.app"

swift build -c release

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp Info.plist "$APP_BUNDLE/Contents/Info.plist"

echo "Built $APP_BUNDLE. Open it with: open \"$APP_BUNDLE\""
