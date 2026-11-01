#!/usr/bin/env python3
"""A running game's processes, for the in-game overlay to tell the game's sound from other apps' and for the
launcher's Playing button to find its window: a JSON list of pids, [] when it isn't running.

Each argument is one way to find it (GameLauncherService.processMatchers gives them); the pids of all of
them together are printed:
  steam:<app id>      everything under `reaper SteamLaunch AppId=<id>` (as game_watch.py finds games)
  lutris:<name>       everything under `lutris-wrapper <name>`
  flatpak:<app id>    everything in its Flatpak sandbox (app-flatpak-<id>-<n>.scope)
  exe:<program>       everything under a process running that program

Usage: game_pids.py <kind:key> […]
"""
import json
import os
import sys


def scan():
    """{pid: (argv, ppid)} of every process that can be read"""
    procs = {}
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
        procs[int(name)] = (argv, int(stat[stat.rfind(b")") + 2:].split()[1]))
    return procs


SCOPES = f"/sys/fs/cgroup/user.slice/user-{os.getuid()}.slice/user@{os.getuid()}.service/app.slice"


def flatpak_pids(app):
    """Everything in the app's sandbox: its scope's own list (app-flatpak-<id>-<n>.scope), not every process's"""
    out = []
    try:
        scopes = [d for d in os.listdir(SCOPES) if d.startswith(f"app-flatpak-{app}-") and d.endswith(".scope")]
    except OSError:
        return out
    for scope in scopes:
        try:
            with open(f"{SCOPES}/{scope}/cgroup.procs") as f:
                out.extend(int(line) for line in f if line.strip().isdigit())
        except OSError:
            pass
    return out


def roots(procs, kind, key):
    """The game's own processes for one matcher, before their children are added"""
    if kind == "steam":
        tag = f"AppId={key}".encode()
        return [p for p, (argv, _) in procs.items() if b"SteamLaunch" in argv and tag in argv]
    if kind == "lutris":
        name = key.encode()
        out = []
        for p, (argv, _) in procs.items():
            head = argv[0] if argv else b""
            if head.startswith(b"lutris-wrapper: ") and head[len(b"lutris-wrapper: "):].strip() == name:
                out.append(p)  # Titled by setproctitle
            elif any(a.endswith(b"lutris-wrapper") and i + 1 < len(argv) and argv[i + 1] == name for i, a in enumerate(argv)):
                out.append(p)
        return out
    if kind == "flatpak":
        return flatpak_pids(key)
    if kind == "exe":
        return [p for p, (argv, _) in procs.items() if argv and os.path.basename(argv[0].decode(errors="replace")) == key]
    return []


def game_pids(matchers):
    """Sorted pids of everything matched, and everything under it"""
    procs = scan()
    children = {}
    for pid, (_, ppid) in procs.items():
        children.setdefault(ppid, []).append(pid)
    pids, todo = set(), []
    for matcher in matchers:
        kind, _, key = matcher.partition(":")
        if key:
            todo.extend(roots(procs, kind, key))
    while todo:
        pid = todo.pop()
        if pid not in pids:
            pids.add(pid)
            todo.extend(children.get(pid, []))
    return sorted(pids)


if __name__ == "__main__":
    # A bare app id, as before: a Steam game
    args = [a if ":" in a else f"steam:{a}" for a in sys.argv[1:]]
    print(json.dumps(game_pids(args)))
