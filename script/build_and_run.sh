#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="CodexProxyLauncher"
DISPLAY_NAME="codex-proxy"
BUNDLE_ID="com.local.codex-proxy"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/$DISPLAY_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
INSTALL_PATH="/Applications/$DISPLAY_NAME.app"

build_app() {
  "$ROOT_DIR/script/build_app.sh" >/dev/null
}

stop_launcher() {
  /usr/bin/pkill -x "$APP_NAME" >/dev/null 2>&1 || true
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

usage() {
  echo "usage: $0 [run|build|--build-only|install|--install|--debug|--logs|--telemetry|--verify]" >&2
}

case "$MODE" in
  run)
    stop_launcher
    build_app
    open_app
    ;;
  build|--build-only)
    build_app
    echo "$APP_BUNDLE"
    ;;
  install|--install)
    build_app
    rm -rf "$INSTALL_PATH"
    /usr/bin/ditto "$APP_BUNDLE" "$INSTALL_PATH"
    /usr/bin/codesign --verify --deep --strict --verbose=2 "$INSTALL_PATH"
    echo "$INSTALL_PATH"
    ;;
  --debug|debug)
    stop_launcher
    build_app
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    stop_launcher
    build_app
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    stop_launcher
    build_app
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    stop_launcher
    build_app
    open_app
    sleep 1
    /usr/bin/pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    usage
    exit 2
    ;;
esac
