#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="TextFix.app"
APP_BUNDLE="${ROOT_DIR}/dist/${APP_NAME}"
APP_CONTENTS="${APP_BUNDLE}/Contents"
APP_BINARY="${ROOT_DIR}/.build/release/TextFix"
INFO_PLIST="${ROOT_DIR}/Packaging/Info.plist"
SIGN_IDENTITY="${TEXTFIX_SIGN_IDENTITY:-}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This builder only supports macOS."
  exit 1
fi

if ! command -v swift >/dev/null 2>&1; then
  echo "swift is required but was not found."
  exit 1
fi

if [[ ! -f "${INFO_PLIST}" ]]; then
  echo "Missing ${INFO_PLIST}."
  exit 1
fi

echo "Building Swift app..."
(
  cd "${ROOT_DIR}"
  swift build -c release
)

if [[ ! -x "${APP_BINARY}" ]]; then
  echo "Build finished, but ${APP_BINARY} was not created."
  exit 1
fi

echo "Assembling ${APP_NAME}..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_CONTENTS}/MacOS" "${APP_CONTENTS}/Frameworks" "${APP_CONTENTS}/Resources"
/usr/bin/ditto "${APP_BINARY}" "${APP_CONTENTS}/MacOS/TextFix"
/usr/bin/ditto "${INFO_PLIST}" "${APP_CONTENTS}/Info.plist"

if command -v xcrun >/dev/null 2>&1; then
  xcrun swift-stdlib-tool \
    --copy \
    --scan-executable "${APP_CONTENTS}/MacOS/TextFix" \
    --platform macosx \
    --destination "${APP_CONTENTS}/Frameworks" >/dev/null
fi

if [[ -n "${SIGN_IDENTITY}" ]]; then
  echo "Signing ${APP_NAME} with ${SIGN_IDENTITY}..."
  codesign --force --deep --sign "${SIGN_IDENTITY}" --timestamp=none "${APP_BUNDLE}"
  codesign --verify --deep --strict "${APP_BUNDLE}"
else
  cat <<EOF
Note: ${APP_NAME} was built without a persistent code-signing identity.
macOS Accessibility and Input Monitoring permissions can reset across rebuilds for ad-hoc signed apps.
Set TEXTFIX_SIGN_IDENTITY to a valid code-signing identity before running this script to keep a stable app identity.
EOF
fi

echo "Built ${APP_BUNDLE}"
