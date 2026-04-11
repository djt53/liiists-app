#!/bin/bash
set -eo pipefail

cd "$(dirname "$0")"

# Regenerate Xcode project
xcodegen generate

# Bump build number
CURRENT=$(grep 'CURRENT_PROJECT_VERSION:' project.yml | awk '{print $2}')
NEXT=$((CURRENT + 1))
sed -i '' "s/CURRENT_PROJECT_VERSION: $CURRENT/CURRENT_PROJECT_VERSION: $NEXT/" project.yml
echo "Build number: $CURRENT → $NEXT"

# Regenerate after version bump
xcodegen generate

# Archive
xcodebuild archive -scheme liiists \
  -archivePath build/liiists.xcarchive \
  -destination 'generic/platform=iOS' \
  2>&1 | tail -3

if [ ${PIPESTATUS[0]} -ne 0 ]; then echo "✗ Archive failed"; exit 1; fi

# Export & upload
xcodebuild -exportArchive \
  -archivePath build/liiists.xcarchive \
  -exportOptionsPlist build/ExportOptions.plist \
  -exportPath build/export \
  2>&1 | tail -5

if [ ${PIPESTATUS[0]} -ne 0 ]; then echo "✗ Export/upload failed"; exit 1; fi

echo "✓ Build $NEXT uploaded to App Store Connect"
