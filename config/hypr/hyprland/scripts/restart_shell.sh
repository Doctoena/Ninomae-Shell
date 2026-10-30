#!/usr/bin/env bash
# Restarts the shell cleanly. `qs kill` asks it to quit, which also stops its watchers and monitors
# (inotifywait, …); killall would leave those running. It returns before the shell is gone, so wait
# up to 3 s for it, and only then force it (a hung shell).
#   restart_shell.sh [config]   (default: Ninomae)
config="${1:-Ninomae}"
qs kill -c "$config" >/dev/null 2>&1
for _ in $(seq 30); do
    pgrep -x qs >/dev/null || pgrep -x quickshell >/dev/null || break
    sleep 0.1
done
killall -q -w qs quickshell
setsid -f qs -c "$config" >/dev/null 2>&1
