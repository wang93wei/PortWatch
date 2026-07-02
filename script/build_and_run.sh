#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

APP_NAME="PortWatch"
PROJECT_PATH="${ROOT_DIR}/PortWatch.xcodeproj"
SCHEME="PortWatch"
CONFIG="${CONFIG:-Debug}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-${ROOT_DIR}/build/DerivedData}"
APP_PATH="${DERIVED_DATA_PATH}/Build/Products/${CONFIG}/${APP_NAME}.app"
VERIFY=false

usage() {
    echo "Usage: $0 [--verify]" >&2
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --verify)
            VERIFY=true
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage
            exit 2
            ;;
    esac
    shift
done

pkill -x "${APP_NAME}" 2>/dev/null || true

xcodebuild \
    -project "${PROJECT_PATH}" \
    -scheme "${SCHEME}" \
    -configuration "${CONFIG}" \
    -derivedDataPath "${DERIVED_DATA_PATH}" \
    build

open -n "${APP_PATH}"

if [[ "${VERIFY}" == true ]]; then
    sleep 2
    pgrep -x "${APP_NAME}" >/dev/null
fi
