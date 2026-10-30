#!/usr/bin/env python3
"""Follows a game launched from the launcher, so its session counts from when it starts to when it
exits (sessions used to run until the launcher was next opened).

Usage: watch_game.py steam <app id> <grace seconds>
       watch_game.py lutris <game name> <grace seconds>
       watch_game.py flatpak <app id> <grace seconds>    (a game added by hand that's a Flatpak)
       watch_game.py exe <program path or name> <grace seconds>    (any other one added by hand)
Prints one event per line (times in milliseconds since the epoch):
  started <ms>   the game's process is up
  alive <ms>     still running (once a minute)
  ended <ms>     it exited; the script exits too
  never          it didn't come up within the grace period
Steam runs every game under `reaper SteamLaunch AppId=<id> -- …`, Lutris under
`lutris-wrapper <game name> …` (titled "lutris-wrapper: <name>" when setproctitle is installed).
A Flatpak runs in its own app-flatpak-<app id>-<n>.scope (its launcher and the game it starts alike), so
one folder listing finds it; a plain program is matched by its executable's name.
"""
import os
import sys
import time

SCOPES = f"/sys/fs/cgroup/user.slice/user-{os.getuid()}.slice/user@{os.getuid()}.service/app.slice"

def flatpak_running(app):
    try:
        return any(n.startswith(f"app-flatpak-{app}-") and n.endswith(".scope") for n in os.listdir(SCOPES))
    except OSError:
        return False

def matches(argv, kind, key):
    if kind == "exe":
        name = os.path.basename(key)
        return bool(argv and argv[0]) and (argv[0] == key or os.path.basename(argv[0]) == name)
    if kind == "steam":
        return "SteamLaunch" in argv and f"AppId={key}" in argv
    if argv and argv[0].startswith(f"lutris-wrapper: {key}"):
        return True
    return any(a.endswith("/lutris-wrapper") and argv[i + 1:i + 2] == [key] for i, a in enumerate(argv))

def running(kind, key):
    if kind == "flatpak":
        return flatpak_running(key)
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                argv = f.read().decode(errors="replace").rstrip("\0").split("\0")
        except OSError: # Exited while scanning
            continue
        if matches(argv, kind, key):
            return True
    return False

def say(*words):
    print(*words, flush=True)

def now():
    return int(time.time() * 1000)

def main():
    kind, key, grace = sys.argv[1], sys.argv[2], float(sys.argv[3])
    deadline = time.monotonic() + grace
    while not running(kind, key):
        if time.monotonic() > deadline:
            say("never")
            return
        time.sleep(2)
    say("started", now())
    last_alive = time.monotonic()
    misses = 0
    while misses < 2: # Two scans in a row, so one racing a process change can't end the session
        time.sleep(5)
        misses = 0 if running(kind, key) else misses + 1
        if misses == 0 and time.monotonic() - last_alive >= 60:
            say("alive", now())
            last_alive = time.monotonic()
    say("ended", now())

if __name__ == "__main__":
    try:
        main()
    except (KeyboardInterrupt, BrokenPipeError): # Shell stopped or restarted
        pass
