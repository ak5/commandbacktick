#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift build -c release --jobs 1
bin_dir=$(swift build -c release --show-bin-path)
app="dist/CommandBacktick.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/CommandBacktick" "$app/Contents/MacOS/CommandBacktick"
cp Info.plist "$app/Contents/Info.plist"
codesign --force --sign - --identifier com.ak5.commandbacktick "$app"
printf 'Built %s\n' "$app"
