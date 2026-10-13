#!/bin/zsh
# Draws the iPhone and Mac app icons from Frank's face code (scripts/icon/AppIcon.swift) into the asset catalogs.
set -euo pipefail
cd "$(dirname "$0")/.."

PHONE=iOS/Assets.xcassets/AppIcon.appiconset
MAC=Mac/Assets.xcassets/AppIcon.appiconset
mkdir -p "$PHONE" "$MAC"

BUILD=$(mktemp -d)
swiftc -O -parse-as-library -module-name AppIcon -o "$BUILD/appicon" \
  Shared/FrankLink.swift Shared/Palette.swift iOS/App/Theme.swift \
  iOS/Face/FaceView.swift iOS/Face/BisonParts.swift iOS/Face/BlobShape.swift \
  scripts/icon/AppIcon.swift
"$BUILD/appicon" "$PHONE" "$MAC"
rm -rf "$BUILD"
echo "Icons written to $PHONE and $MAC"
