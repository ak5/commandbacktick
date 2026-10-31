#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
if [ "${COMMAND_BACKTICK_SIGNING_IDENTITY+x}" = x ]; then
    signing_identity="$COMMAND_BACKTICK_SIGNING_IDENTITY"
elif [ -f signing.local.txt ]; then
    signing_identity=$(cat signing.local.txt)
else
    signing_identity="-"
fi
[ -n "$signing_identity" ] || { printf 'Signing identity must not be empty.\n' >&2; exit 1; }
swift build -c release --jobs 1
bin_dir=$(swift build -c release --show-bin-path)
app="dist/CommandBacktick.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/CommandBacktick" "$app/Contents/MacOS/CommandBacktick"
cp Info.plist "$app/Contents/Info.plist"
codesign --force --sign "$signing_identity" --identifier com.ak5.commandbacktick "$app"
codesign --verify --strict "$app"
printf 'Built %s\n' "$app"
