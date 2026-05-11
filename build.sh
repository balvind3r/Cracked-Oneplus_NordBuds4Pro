#!/bin/bash
# Build NordBuds.app from nordbuds.swift + Info.plist and ad-hoc sign it.
# macOS requires a real .app bundle with NSBluetoothAlwaysUsageDescription
# in Info.plist for TCC to grant Bluetooth access — a bare CLI binary
# crashes silently with a privacy violation.
set -euo pipefail

cd "$(dirname "$0")"

APP="NordBuds.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"

swiftc nordbuds.swift -O -o "$APP/Contents/MacOS/nordbuds"
codesign --force --deep --sign - "$APP"

echo "[OK] Built $APP"
codesign -dv "$APP" 2>&1 | head -4
