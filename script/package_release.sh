#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-v1.0.0}"
APP_NAME="codex-proxy"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
ZIP_PATH="$DIST_DIR/$APP_NAME-$VERSION-macos-arm64.zip"
SHA_PATH="$ZIP_PATH.sha256"

"$ROOT_DIR/script/build_app.sh" >/dev/null

rm -f "$ZIP_PATH" "$SHA_PATH"
cd "$DIST_DIR"
/usr/bin/ditto -c -k --keepParent "$APP_NAME.app" "$ZIP_PATH"
/usr/bin/shasum -a 256 "$ZIP_PATH" > "$SHA_PATH"

echo "$ZIP_PATH"
echo "$SHA_PATH"
