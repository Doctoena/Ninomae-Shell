#!/usr/bin/env bash
# Rebuilds the clipboard history database so it takes only the space its entries need.
# cliphist's database file never shrinks: deleted entries (the 300-item cap, the image cap in
# cliphist_store.sh) leave free pages behind, and it had grown to ~106 MB holding ~17 MB.
# Copies the entries oldest first into a new file, then swaps it in. Entry numbers change,
# so the shell's decoded previews (keyed by number) are cleared too.
# Usage: cliphist_compact.sh [db path]   (default: cliphist's own)
set -euo pipefail
db="${1:-${XDG_CACHE_HOME:-$HOME/.cache}/cliphist/db}"
[[ -f $db ]] || exit 0
new="$db.compact.$$"
trap 'rm -f "$new"' EXIT

# Holds the store script's lock: a copy made meanwhile waits instead of going to the old file
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/cliphist.lock"
flock 9

cliphist -db-path "$db" list | cut -f1 | tac | while read -r id; do
    printf '%s\t\n' "$id" | cliphist -db-path "$db" decode | cliphist -db-path "$new" -max-items 300 store
done
before=$(stat -c %s "$db"); after=$(stat -c %s "$new")
mv -f "$new" "$db"
rm -rf "${XDG_RUNTIME_DIR:-/tmp}"/quickshell/media/cliphist/* 2>/dev/null || true
echo "cliphist: $((before / 1024 / 1024)) MB -> $((after / 1024 / 1024)) MB"
