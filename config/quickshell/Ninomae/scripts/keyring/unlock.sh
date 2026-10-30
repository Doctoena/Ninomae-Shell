#!/usr/bin/env bash
# Based on https://unix.stackexchange.com/a/602935

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Skip if already unlocked
if "${SCRIPT_DIR}/is_unlocked.sh"; then
    exit 1
fi

# Prompt for password if not provided (the lock screen passes it in UNLOCK_PASSWORD)
if [[ -z "${UNLOCK_PASSWORD}" ]]; then
    echo -n 'Login password: ' >&2
    read -rs UNLOCK_PASSWORD || exit 1
    echo '' >&2
fi

# Restart the daemon unlocked with the login password. It prints its environment for a caller to
# export; this script exits right after, so there's nothing to export it into
killall -q -u "$(whoami)" gnome-keyring-daemon
printf '%s' "${UNLOCK_PASSWORD}" | gnome-keyring-daemon --daemonize --login >/dev/null
