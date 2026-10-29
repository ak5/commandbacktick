#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

source_app="dist/CommandBacktick.app"
destination="$HOME/Applications/CommandBacktick.app"
[ -d "$source_app" ] || { printf 'Build first: nice -n 10 ./scripts/build-app.sh\n' >&2; exit 1; }
codesign --verify --strict "$source_app"
mkdir -p "$HOME/Applications"
stage_dir=$(mktemp -d "$HOME/Applications/.commandbacktick-install.XXXXXX")
trap 'rm -rf "$stage_dir"' EXIT
ditto "$source_app" "$stage_dir/CommandBacktick.app"
codesign --verify --strict "$stage_dir/CommandBacktick.app"

pkill -x CommandBacktick || true
backup=""
if [ -e "$destination" ]; then
    backup_dir=$(mktemp -d "${TMPDIR:-/tmp}/commandbacktick-backup.XXXXXX")
    backup="$backup_dir/CommandBacktick.app"
    mv "$destination" "$backup"
fi
# Replace the bundle rather than overwrite an executable with a cached signing identity.
if ! mv "$stage_dir/CommandBacktick.app" "$destination"; then
    if [ -n "$backup" ]; then mv "$backup" "$destination"; fi
    exit 1
fi
printf 'Installed %s\n' "$destination"
if [ -n "$backup" ]; then printf 'Previous build: %s\n' "$backup"; fi
printf 'Approve permissions for this installed copy, then open it. See README.md.\n'
