#!/bin/sh
# Puts the DS Bot plugin where a plugin install reads it from, so the app can
# install it without fetching from GitHub. Idempotent: it only copies a
# tarball that is missing or differs, and never touches the DSH profile (an
# install still owns that).
set -eu
src="/opt/dsh-go/bundled/ds-bot-1.3.6.tgz"
dst_dir="$HOME/.dsh/local-bundles"
dst="$dst_dir/ds-bot-1.3.6.tgz"
[ -f "$src" ] || exit 0
mkdir -p "$dst_dir"
if [ ! -f "$dst" ] || ! cmp -s "$src" "$dst"; then
  cp "$src" "$dst.tmp"
  mv "$dst.tmp" "$dst"
fi
