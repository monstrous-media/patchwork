#!/bin/sh
# The user guide lives in the app bundle (Sources/PatchworkApp/Resources/guide.md) and is mirrored to docs/
# for a static site, together with the generated parameter reference. Run after editing the guide or
# ParameterHelp.swift.
set -e
cd "$(dirname "$0")/.."
cp Sources/PatchworkApp/Resources/guide.md docs/guide.md
if [ -x .build/debug/patchwork ]; then
  .build/debug/patchwork params > docs/parameters.md
  echo "docs/guide.md and docs/parameters.md synced"
else
  echo "docs/guide.md synced (build patchwork with 'swift build' to regenerate docs/parameters.md)"
fi
