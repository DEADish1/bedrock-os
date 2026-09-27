#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
target="$root/os/config/includes.chroot/usr/share/bedrock/management-ui"
[ ! -e "$target" ] && [ ! -L "$target" ] || { printf 'error: refusing to overwrite an existing UI stage\n' >&2; exit 1; }
[ "$(uname -m)" = x86_64 ] || { printf 'error: UI image builder currently requires x86_64 Linux\n' >&2; exit 1; }
: "${BEDROCK_SOURCE_COMMIT:?source commit is required}"
mkdir -p "$root/os/.build"
work=$(mktemp -d "$root/os/.build/management-ui.XXXXXX")
target_created=0
cleanup() {
  status=$?
  if [ "$status" -ne 0 ] && [ "$target_created" -eq 1 ]; then rm -rf -- "$target"; fi
  rm -rf -- "$work"
  exit "$status"
}
trap cleanup EXIT INT TERM
# SHA-256 pinned from https://nodejs.org/dist/v24.16.0/SHASUMS256.txt.
python3 - "$work/node.tar.gz" <<'PY'
import sys, urllib.request
urllib.request.urlretrieve("https://nodejs.org/dist/v24.16.0/node-v24.16.0-linux-x64.tar.gz", sys.argv[1])
PY
printf '%s  %s\n' '2faf6a387e9b62b888e21c54f01249fb27537ffecf1842f29f4c919d0a59a0ff' "$work/node.tar.gz" | sha256sum -c -
tar -xzf "$work/node.tar.gz" --no-same-owner -C "$work"
PATH="$work/node-v24.16.0-linux-x64/bin:$PATH"
export PATH
project="$work/project"
mkdir -p "$project/app" "$project/scripts"
cp "$root/package.json" "$root/package-lock.json" "$root/tsconfig.json" "$root/tsconfig.installed.json" "$root/vite.installed.config.ts" "$project/"
cp "$root/app/page.tsx" "$root/app/globals.css" "$root/app/novnc.d.ts" "$project/app/"
cp "$root/scripts/test-installed-ui.mjs" "$root/scripts/manifest-installed-ui.mjs" "$project/scripts/"
cp -R "$root/management-ui" "$root/public" "$project/"
cd "$project"
npm ci --no-audit --no-fund
npm run typecheck:installed-ui
npm run build:installed-ui
npm run test:installed-ui
node scripts/manifest-installed-ui.mjs
mkdir "$target"
target_created=1
cp -R dist/management-ui/. "$target/"
printf 'Staged verified static management UI for the OS image.\n'
