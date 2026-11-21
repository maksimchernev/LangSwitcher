#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
swift build -c release --product LangSwitcher --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security
app="${LANGSWITCHER_OUTPUT_DIR:-$PWD/dist}/LangSwitcher.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/LangSwitcher "$app/Contents/MacOS/LangSwitcher"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp -R Resources/AppIcon.icns Resources/en.lproj Resources/ru.lproj "$app/Contents/Resources/"
codesign --force --sign - --identifier local.langswitcher.app "$app"
codesign --verify --strict "$app"
touch -r "$app/Contents/MacOS/LangSwitcher" "$app"
printf '%s\n' "$app"
