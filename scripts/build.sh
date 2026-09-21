#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate --quiet
fi
xcodebuild -project Minato.xcodeproj -scheme Minato -configuration Debug -derivedDataPath build build "CODE_SIGN_IDENTITY=${MINATO_CODE_SIGN_IDENTITY:-Apple Development}"
echo "Built: $PWD/build/Build/Products/Debug/Minato.app"
