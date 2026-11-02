#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA="$ROOT_DIR/build/DerivedData"

INSTALL=false
APPS=()

for arg in "$@"; do
  if [[ "$arg" == "--install" ]]; then
    INSTALL=true
  else
    APPS+=("$arg")
  fi
done

if [[ ${#APPS[@]} -eq 0 ]]; then
  APPS=("Messenger" "Marketplace" "Groups")
fi

for APP in "${APPS[@]}"; do
  echo "Building $APP ($CONFIGURATION)..."
  xcodebuild \
    -project Messenger.xcodeproj \
    -scheme "$APP" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA" \
    build

  BUILT_APP="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP.app"
  OUTPUT_APP="$ROOT_DIR/build/$APP.app"
  rm -rf "$OUTPUT_APP"
  ditto "$BUILT_APP" "$OUTPUT_APP"
  echo "Built: $OUTPUT_APP"

  if [[ "$INSTALL" == "true" ]]; then
    TARGET_DIR="/Applications"
    if [[ ! -w "$TARGET_DIR" ]]; then
      TARGET_DIR="$HOME/Applications"
      mkdir -p "$TARGET_DIR"
    fi
    rm -rf "$TARGET_DIR/$APP.app"
    ditto "$OUTPUT_APP" "$TARGET_DIR/$APP.app"
    echo "Installed to: $TARGET_DIR/$APP.app"
  fi
done
