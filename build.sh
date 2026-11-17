#!/bin/zsh
# Builds build/BrowserDeck.app. `./build.sh install` also copies it to ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"

APP=build/BrowserDeck.app
ICON=Resources/AppIcon.icns

if [[ ! -f $ICON ]]; then
  echo "→ icon"
  tmp=$(mktemp -d)
  swift scripts/make_icon.swift "$tmp/icon_1024.png"
  set_dir="$tmp/AppIcon.iconset"
  mkdir -p "$set_dir"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$tmp/icon_1024.png" --out "$set_dir/icon_${s}x${s}.png" >/dev/null
    d=$((s * 2))
    sips -z $d $d "$tmp/icon_1024.png" --out "$set_dir/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$set_dir" -o "$ICON"
  cp "$tmp/icon_1024.png" Resources/icon_1024.png
fi

echo "→ compile"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -parse-as-library -target arm64-apple-macos14.0 \
  Sources/*.swift -o "$APP/Contents/MacOS/BrowserDeck"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"

echo "→ sign (ad-hoc)"
codesign --force --sign - "$APP"

if [[ ${1:-} == install ]]; then
  mkdir -p ~/Applications
  rm -rf ~/Applications/BrowserDeck.app
  cp -R "$APP" ~/Applications/
  echo "✓ installed to ~/Applications/BrowserDeck.app"
else
  echo "✓ $APP"
fi
