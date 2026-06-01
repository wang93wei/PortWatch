#!/usr/bin/env bash
# Build PortWatch SPM target and wrap the binary in a real .app bundle.
# Usage: script/build_app.sh            # release (default)
#        CONFIG=debug script/build_app.sh
set -euo pipefail

CONFIG="${CONFIG:-release}"
APP_NAME="PortWatch"
APP_DIR="build/${APP_NAME}.app"
# SwiftPM resource bundle for the "PortWatch" target in package "PortWatch":
#   .build/<config>/PortWatch_PortWatch.bundle/Info.plist
BUNDLE_RESOURCES=".build/${CONFIG}/${APP_NAME}_${APP_NAME}.bundle"

echo "==> swift build -c ${CONFIG}"
swift build -c "${CONFIG}"

BIN=".build/${CONFIG}/${APP_NAME}"
if [[ ! -f "$BIN" ]]; then
    echo "error: built binary not found at $BIN" >&2
    exit 1
fi

echo "==> assembling ${APP_DIR}"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "$BIN" "${APP_DIR}/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_DIR}/Contents/MacOS/${APP_NAME}"

# Prefer the Info.plist that SwiftPM copied into the resource bundle.
PLIST_SRC="${BUNDLE_RESOURCES}/Info.plist"
if [[ ! -f "$PLIST_SRC" ]]; then
    # Fallback: copy from source tree (lets the script work even before
    # `swift build` has produced the resource bundle on first run).
    PLIST_SRC="Sources/PortWatch/Resources/Info.plist"
fi
cp "$PLIST_SRC" "${APP_DIR}/Contents/Info.plist"

echo "==> done. Launch with:  open ${APP_DIR}"
