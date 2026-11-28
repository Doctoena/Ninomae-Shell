#!/usr/bin/env bash
# Clipboard history's store step (run by `wl-paste --watch` for each copy, the copy on stdin).
# Skips copies made from a password manager: cliphist already leaves out ones marked secret
# (x-kde-passwordManagerHint, passed on as CLIPBOARD_STATE=sensitive), but Bitwarden's desktop app
# doesn't mark what it copies, so its passwords were kept in the history on disk.
# Pasting is unaffected: only the history skips them.
class="$(hyprctl activewindow -j 2>/dev/null | jq -r '.class // empty' 2>/dev/null)"
case "${class,,}" in
    bitwarden | org.keepassxc.keepassxc | 1password)
        cat >/dev/null # Take the copy, so wl-paste doesn't see a broken pipe
        exit 0
        ;;
esac
# One at a time, and never while cliphist_compact.sh is swapping the database
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/cliphist.lock"
flock 9
cliphist -max-items 300 store || exit
# Images are capped separately: a few 3-4 MB photos had made up 77 MB of a 106 MB history.
# The newest 40 stay (~17 MB); text entries keep the 300 limit
cliphist list | grep -P '^\d+\t\[\[ binary data' | tail -n +41 | cliphist delete
# The database file never shrinks on its own: rebuild it if it's grown well past that
db="${XDG_CACHE_HOME:-$HOME/.cache}/cliphist/db"
if (( $(stat -c %s "$db" 2>/dev/null || echo 0) > 64 * 1024 * 1024 )); then
    flock -u 9
    setsid -f "$(dirname "$0")/cliphist_compact.sh" >/dev/null 2>&1
fi
