#!/bin/bash
# Zips build/Kibbit.app into dist/ with the fixed asset names install.sh downloads
# (Kibbit.zip + Kibbit.zip.sha256), then proves the installer works against them.
set -euo pipefail
cd "$(dirname "$0")/.."

rm -rf dist && mkdir -p dist
ditto -c -k --keepParent build/Kibbit.app dist/Kibbit.zip
(cd dist && shasum -a 256 Kibbit.zip > Kibbit.zip.sha256)

TARGET="$(mktemp -d)"
trap 'rm -rf "$TARGET"' EXIT
KIBBIT_BASE_URL="file://$PWD/dist" KIBBIT_DIR="$TARGET" KIBBIT_NO_OPEN=1 ./install.sh
codesign --verify --strict "$TARGET/Kibbit.app"
lipo -archs "$TARGET/Kibbit.app/Contents/MacOS/Kibbit"
echo "Packaged dist/Kibbit.zip ($(du -h dist/Kibbit.zip | cut -f1))"
