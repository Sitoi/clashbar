#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$ROOT/Scripts"
STAGE="${1:-all}"

run_preprocess() {
  "$SCRIPTS_DIR/preprocess.sh"
}

run_package_app() {
  "$SCRIPTS_DIR/package_app.sh"
}

run_make_dmg() {
  "$SCRIPTS_DIR/make_dmg.sh"
}

usage() {
  cat <<'EOF'
Usage: Scripts/build.sh [stage]

Stages:
  preprocess   Run preprocessing only (download resources, prepare icon).
  package      Build and package app bundle only.
  dmg          Build dmg from existing app bundle only.
  app          Run preprocess + package.
  all          Run preprocess + package + dmg (default).

Environment:
  PREPARE_MIHOMO_BINARY=0  Skip preprocessing/downloading mihomo.
  BUNDLE_MIHOMO_BINARY=0   Build a no-core app/dmg without bundled mihomo.
EOF
}

case "$STAGE" in
  preprocess)
    run_preprocess
    ;;
  package)
    run_package_app
    ;;
  dmg)
    run_make_dmg
    ;;
  app)
    run_preprocess
    run_package_app
    ;;
  all)
    run_preprocess
    run_package_app
    run_make_dmg
    ;;
  -h | --help | help)
    usage
    ;;
  *)
    echo "Unknown stage: $STAGE" >&2
    usage >&2
    exit 1
    ;;
esac
