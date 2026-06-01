#!/usr/bin/env bash
# Build a real .app bundle, then launch it via `open` so AppKit/MenuBarExtra
# can register properly (a bare `swift run` binary will not show a menu bar item).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"${SCRIPT_DIR}/build_app.sh"
open "build/PortWatch.app"
