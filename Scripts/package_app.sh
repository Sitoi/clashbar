#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${APP_NAME:-ClashBar}"
BUNDLE_ID="${BUNDLE_ID:-com.clashbar}"
APP_VERSION="${APP_VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
TARGET_ARCH="${TARGET_ARCH:-}"
PREPROCESS_DIR="${PREPROCESS_DIR:-$ROOT/dist/preprocess}"
PREPROCESSED_ICON_PATH="${PREPROCESSED_ICON_PATH:-$PREPROCESS_DIR/${APP_NAME}.icns}"
PREPROCESSED_MIHOMO_PATH="${PREPROCESSED_MIHOMO_PATH:-$PREPROCESS_DIR/mihomo}"
REQUIRE_MIHOMO_BINARY="${REQUIRE_MIHOMO_BINARY:-1}"
BUNDLE_MIHOMO_BINARY="${BUNDLE_MIHOMO_BINARY:-1}"

APP="$ROOT/dist/${APP_NAME}.app"
HELPER_LABEL="com.clashbar.helper"
HELPER_PLIST_SOURCE="$ROOT/Sources/Helper/LaunchDaemons/${HELPER_LABEL}.plist"

cd "$ROOT"

BUILD_ARGS=(-c release)
if [ -n "$TARGET_ARCH" ]; then
  BUILD_ARGS+=(--arch "$TARGET_ARCH")
fi
swift build "${BUILD_ARGS[@]}"

if [ -n "$TARGET_ARCH" ]; then
  BIN_CANDIDATE="$ROOT/.build/${TARGET_ARCH}-apple-macosx/release/ClashBar"
  RESOURCE_BUNDLE_CANDIDATE="$ROOT/.build/${TARGET_ARCH}-apple-macosx/release/ClashBar_ClashBar.bundle"
  HELPER_BIN_CANDIDATE="$ROOT/.build/${TARGET_ARCH}-apple-macosx/release/ClashBarProxyHelper"
  BIN_PATTERN="*/${TARGET_ARCH}-apple-macosx/release/ClashBar"
  RESOURCE_BUNDLE_PATTERN="*/${TARGET_ARCH}-apple-macosx/release/ClashBar_ClashBar.bundle"
  HELPER_PATTERN="*/${TARGET_ARCH}-apple-macosx/release/ClashBarProxyHelper"
else
  BIN_CANDIDATE="$ROOT/.build/release/ClashBar"
  RESOURCE_BUNDLE_CANDIDATE="$ROOT/.build/release/ClashBar_ClashBar.bundle"
  HELPER_BIN_CANDIDATE="$ROOT/.build/release/ClashBarProxyHelper"
  BIN_PATTERN="*/release/ClashBar"
  RESOURCE_BUNDLE_PATTERN="*/release/ClashBar_ClashBar.bundle"
  HELPER_PATTERN="*/release/ClashBarProxyHelper"
fi

resolve_build_artifact() {
  local candidate="$1"
  local artifact_type="$2"
  local release_pattern="$3"

  if [ "$artifact_type" = "file" ] && [ -f "$candidate" ]; then
    echo "$candidate"
    return
  fi
  if [ "$artifact_type" = "dir" ] && [ -d "$candidate" ]; then
    echo "$candidate"
    return
  fi

  local find_type="f"
  if [ "$artifact_type" = "dir" ]; then
    find_type="d"
  fi
  find "$ROOT/.build" -path "$release_pattern" -type "$find_type" | head -n 1 || true
}

resolve_mihomo_install_path() {
  local filename="${1:-mihomo}"
  local bundle_dir="$APP/Contents/Resources/ClashBar_ClashBar.bundle"
  local resources_dir="$APP/Contents/Resources"
  local candidates=(
    "$bundle_dir/$filename"
    "$bundle_dir/bin/$filename"
    "$bundle_dir/Resources/bin/$filename"
    "$resources_dir/bin/$filename"
    "$resources_dir/Resources/bin/$filename"
    "$resources_dir/$filename"
  )
  local path=""

  for path in "${candidates[@]}"; do
    if [ -f "$path" ]; then
      echo "$path"
      return
    fi
  done

  for path in "${candidates[@]}"; do
    if [ -d "$(dirname "$path")" ]; then
      echo "$path"
      return
    fi
  done

  echo "$bundle_dir/$filename"
}

remove_bundled_mihomo_candidates() {
  local filename="$1"
  local path=""

  while IFS= read -r path; do
    [ -n "$path" ] || continue
    if [ -f "$path" ]; then
      rm -f "$path"
    fi
  done < <(printf '%s\n' \
    "$(resolve_mihomo_install_path "$filename")" \
    "$APP/Contents/Resources/ClashBar_ClashBar.bundle/bin/$filename" \
    "$APP/Contents/Resources/ClashBar_ClashBar.bundle/Resources/bin/$filename" \
    "$APP/Contents/Resources/bin/$filename" \
    "$APP/Contents/Resources/Resources/bin/$filename" \
    "$APP/Contents/Resources/$filename" | awk '!seen[$0]++')
}

BIN="$(resolve_build_artifact "$BIN_CANDIDATE" file "$BIN_PATTERN")"
RESOURCE_BUNDLE="$(resolve_build_artifact "$RESOURCE_BUNDLE_CANDIDATE" dir "$RESOURCE_BUNDLE_PATTERN")"
HELPER_BIN="$(resolve_build_artifact "$HELPER_BIN_CANDIDATE" file "$HELPER_PATTERN")"

if [ ! -f "$BIN" ]; then
  echo "Build output not found: $BIN" >&2
  exit 1
fi
if [ ! -d "$RESOURCE_BUNDLE" ]; then
  echo "Resource bundle not found: $RESOURCE_BUNDLE" >&2
  exit 1
fi
if [ ! -f "$HELPER_BIN" ]; then
  echo "Helper build output not found: $HELPER_BIN" >&2
  exit 1
fi
if [ ! -f "$HELPER_PLIST_SOURCE" ]; then
  echo "Helper plist not found: $HELPER_PLIST_SOURCE" >&2
  exit 1
fi

rm -rf "$APP"
mkdir -p \
  "$APP/Contents/MacOS" \
  "$APP/Contents/Resources" \
  "$APP/Contents/Library/HelperTools" \
  "$APP/Contents/Library/LaunchDaemons"

cp "$BIN" "$APP/Contents/MacOS/ClashBar"
chmod +x "$APP/Contents/MacOS/ClashBar"

rm -rf "$APP/Contents/Resources/ClashBar_ClashBar.bundle"
cp -R "$RESOURCE_BUNDLE" "$APP/Contents/Resources/ClashBar_ClashBar.bundle"

if [ "$BUNDLE_MIHOMO_BINARY" = "1" ]; then
  if [ -f "$PREPROCESSED_MIHOMO_PATH" ]; then
    MIHOMO_SOURCE_PATH="$PREPROCESSED_MIHOMO_PATH"
  elif [ -f "$(resolve_mihomo_install_path "mihomo")" ]; then
    MIHOMO_SOURCE_PATH="$(resolve_mihomo_install_path "mihomo")"
  else
    MIHOMO_SOURCE_PATH=""
  fi

  if [ -n "$MIHOMO_SOURCE_PATH" ]; then
    MIHOMO_INSTALL_PATH="$(resolve_mihomo_install_path "mihomo.gz")"
    mkdir -p "$(dirname "$MIHOMO_INSTALL_PATH")"
    remove_bundled_mihomo_candidates "mihomo"
    remove_bundled_mihomo_candidates "mihomo.gz"
    gzip -c "$MIHOMO_SOURCE_PATH" > "$MIHOMO_INSTALL_PATH"
    chmod 644 "$MIHOMO_INSTALL_PATH"
    echo "Bundled compressed mihomo payload: $MIHOMO_INSTALL_PATH"
  elif [ "$REQUIRE_MIHOMO_BINARY" = "1" ]; then
    echo "Missing preprocessed mihomo binary: $PREPROCESSED_MIHOMO_PATH" >&2
    echo "Run ./Scripts/preprocess.sh (or ./Scripts/build.sh app/all) before packaging." >&2
    exit 1
  else
    echo "Warning: preprocessed mihomo binary not found, and no bundled mihomo resource was available."
  fi
else
  remove_bundled_mihomo_candidates "mihomo"
  remove_bundled_mihomo_candidates "mihomo.gz"
  echo "Skipped bundling mihomo payload."
fi

cp "$HELPER_BIN" "$APP/Contents/Library/HelperTools/$HELPER_LABEL"
chmod +x "$APP/Contents/Library/HelperTools/$HELPER_LABEL"
cp "$HELPER_PLIST_SOURCE" "$APP/Contents/Library/LaunchDaemons/${HELPER_LABEL}.plist"

ICON_PLIST_ENTRY=""
if [ -f "$PREPROCESSED_ICON_PATH" ]; then
  cp "$PREPROCESSED_ICON_PATH" "$APP/Contents/Resources/${APP_NAME}.icns"
  ICON_PLIST_ENTRY="<key>CFBundleIconFile</key><string>${APP_NAME}.icns</string>"
else
  echo "Warning: preprocessed icon not found at $PREPROCESSED_ICON_PATH"
fi

if [ "$BUNDLE_MIHOMO_BINARY" = "1" ]; then
  BUNDLES_MIHOMO_CORE_PLIST_VALUE="<true/>"
else
  BUNDLES_MIHOMO_CORE_PLIST_VALUE="<false/>"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>${APP_NAME}</string>
<key>CFBundleDisplayName</key><string>${APP_NAME}</string>
<key>CFBundleExecutable</key><string>ClashBar</string>
<key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>${APP_VERSION}</string>
<key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
$ICON_PLIST_ENTRY
<key>ClashBarBundlesMihomoCore</key>${BUNDLES_MIHOMO_CORE_PLIST_VALUE}
<key>NSAppTransportSecurity</key>
<dict>
<key>NSAllowsArbitraryLoads</key><true/>
</dict>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST

CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
if command -v codesign >/dev/null 2>&1; then
  codesign --force --sign "$CODESIGN_IDENTITY" "$APP/Contents/Library/HelperTools/$HELPER_LABEL"
  codesign --force --sign "$CODESIGN_IDENTITY" "$APP"
fi

echo "Built app: $APP"
