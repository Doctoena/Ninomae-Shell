#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check the lock first: a lookup on a locked keyring makes gnome-keyring pop up its own password
# dialog ("The login keyring did not get unlocked…"), e.g. when the shell starts. Locked = try later
# (the lock screen looks again after it unlocks the keyring)
if ! "${SCRIPT_DIR}/is_unlocked.sh" 2>/dev/null; then
    echo 'locked'
    exit 2
fi
data=$(secret-tool lookup 'application' 'ninomae-shell')
if [[ -z "$data" ]]; then
    echo 'not found'
    exit 1
fi
echo "$data"
