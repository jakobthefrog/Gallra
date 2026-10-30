#!/bin/bash
# Builds the release app, zips it, and prints the Sparkle signature for appcast.xml.
# Usage: scripts/release.sh   (version comes from MARKETING_VERSION in the Xcode project)
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(grep -m1 MARKETING_VERSION Gallra.xcodeproj/project.pbxproj | sed 's/[^0-9.]//g')
xcodebuild -scheme Gallra -configuration Release -destination 'platform=macOS' \
  -derivedDataPath build-release build | grep -E "error|BUILD"
rm -rf dist && mkdir dist
ditto build-release/Build/Products/Release/Gallra.app dist/Gallra.app
codesign --force --deep -s - dist/Gallra.app
(cd dist && ditto -c -k --keepParent Gallra.app "Gallra-$VERSION.zip")
SIGN=$(ls -d ~/Library/Developer/Xcode/DerivedData/Gallra-*/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update | head -1)
echo "Version $VERSION: dist/Gallra-$VERSION.zip"
"$SIGN" "dist/Gallra-$VERSION.zip"
