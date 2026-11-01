#!/usr/bin/env python3
"""The running Steam game's processes, for the in-game overlay to tell the game's sound from other apps':
a JSON list of pids, everything under `reaper SteamLaunch AppId=<id>` (as game_watch.py finds games).
[] when it isn't running.

Usage: game_pids.py <steam app id>
"""
import json
import os
import sys


def main(appid):
    tag = f"AppId={appid}".encode()
    children, roots = {}, []
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            with open(f"/proc/{name}/stat", "rb") as f:
                stat = f.read()
            with open(f"/proc/{name}/cmdline", "rb") as f:
                argv = f.read().split(b"\0")
        except OSError:
            continue
        ppid = int(stat[stat.rfind(b")") + 2:].split()[1])
        children.setdefault(ppid, []).append(int(name))
        if b"SteamLaunch" in argv and tag in argv:
            roots.append(int(name))
    pids, todo = set(), list(roots)
    while todo:
        pid = todo.pop()
        if pid not in pids:
            pids.add(pid)
            todo.extend(children.get(pid, []))
    print(json.dumps(sorted(pids)))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 and sys.argv[1].isdigit() else "")
