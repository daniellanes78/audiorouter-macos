#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
xcodegen
xcodebuild -project AudioRouter.xcodeproj -scheme AudioRouter -configuration Release -derivedDataPath build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
rm -rf dmg AudioRouter.dmg
mkdir dmg
cp -R build/Build/Products/Release/AudioRouter.app dmg/
ln -s /Applications dmg/Applications
hdiutil create -volname AudioRouter -srcfolder dmg -ov -format UDZO AudioRouter.dmg
rm -rf dmg
echo "Pronto: $(pwd)/AudioRouter.dmg"
