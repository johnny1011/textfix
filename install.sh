#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="TextFix.app"
DIST_APP="${ROOT_DIR}/dist/${APP_NAME}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This installer only supports macOS."
  exit 1
fi

if ! command -v swift >/dev/null 2>&1; then
  echo "swift is required but was not found."
  exit 1
fi

DEFAULT_INSTALL_DIR="/Applications"
if [[ ! -w "${DEFAULT_INSTALL_DIR}" ]]; then
  DEFAULT_INSTALL_DIR="${HOME}/Applications"
fi
INSTALL_DIR="${APP_INSTALL_DIR:-${DEFAULT_INSTALL_DIR}}"
INSTALL_APP="${INSTALL_DIR}/${APP_NAME}"
OPEN_AFTER_INSTALL="${OPEN_AFTER_INSTALL:-1}"

mkdir -p "${INSTALL_DIR}"

"${ROOT_DIR}/build_app.sh"

if [[ ! -d "${DIST_APP}" ]]; then
  echo "Build finished, but ${DIST_APP} was not created."
  exit 1
fi

echo "Installing ${APP_NAME} to ${INSTALL_DIR}..."
/usr/bin/ditto "${DIST_APP}" "${INSTALL_APP}"

cat <<EOF
Installed ${APP_NAME} at:
  ${INSTALL_APP}

Next steps:
  1. Open the app once.
  2. Grant Accessibility permissions (and Input Monitoring if macOS asks).
  3. Open Settings in the menu bar app and add your API key.
  4. Turn on "Open at login" if you want it to start automatically.
EOF

if [[ "${OPEN_AFTER_INSTALL}" == "1" ]]; then
  open "${INSTALL_APP}"
fi
