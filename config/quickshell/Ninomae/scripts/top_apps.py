#!/usr/bin/env python3
"""The apps using the most CPU and memory, for the sidebar's resource monitor. Prints a JSON line every
<interval> seconds. The first comes after half a second (CPU use is a difference between two looks), so
the list is there almost at once:

  {"cpu": [app, …], "mem": [app, …]}
  app = {"name", "appId", "pid", "cpu": 0–1 of the whole CPU, "mem": bytes}
"appId" is the desktop id of the scope it was started in (com.microsoft.VSCode), "" when unknown.

A row is an app, not a process: a browser's or Discord's helpers count toward it. An app is everything
under one process started by the session (by systemd, Hyprland or start-hyprland), past a wrapper script
to the one thing it started (bash → steam). Not by app-*.scope: Electron apps' helpers land in other
apps' scopes. "pid" is the app's own first process, the one to ask to quit. System services
(*.service: PipeWire, …), other users' processes, Hyprland and the shell itself are never listed.

Usage: top_apps.py [interval seconds] [rows]
"""
import json
import os
import sys
import time

INTERVAL = float(sys.argv[1]) if len(sys.argv) > 1 else 3.0
ROWS = int(sys.argv[2]) if len(sys.argv) > 2 else 4
PAGE = os.sysconf("SC_PAGE_SIZE")
TICKS = os.sysconf("SC_CLK_TCK")
CPUS = os.cpu_count() or 1
UID = os.getuid()
HIDDEN = {"Hyprland", "Xwayland", "qs", "quickshell", "systemd", "uwsm", "hypridle", "hyprsunset", "wl-paste", "(sd-pam)"}
SESSION = {"systemd", "Hyprland", "start-hyprland"}  # What starts apps: their children are the apps
WRAPPERS = {"bash", "sh", "dash", "zsh", "fish", "env", "python3", "python", "flatpak", "bwrap", "uwsm-app"}


def read(path):
    try:
        with open(path) as f:
            return f.read()
    except OSError:
        return ""


def scan():
    """{pid: (comm, ppid, cpu ticks, private bytes, systemd unit)} for this user's processes"""
    procs = {}
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        pid = int(name)
        try:
            if os.stat(f"/proc/{pid}").st_uid != UID:
                continue
        except OSError:
            continue
        stat = read(f"/proc/{pid}/stat")
        statm = read(f"/proc/{pid}/statm").split()
        cgroup = read(f"/proc/{pid}/cgroup").strip().rsplit("/", 1)[-1]  # Its unit: *.service, *.scope
        if not stat or len(statm) < 3:
            continue
        comm = stat[stat.find("(") + 1:stat.rfind(")")]
        fields = stat[stat.rfind(")") + 2:].split()
        # resident − shared: what the process holds itself, so a browser's many processes don't each count
        # the libraries they share
        private = max(0, int(statm[1]) - int(statm[2])) * PAGE
        procs[pid] = (comm, int(fields[1]), int(fields[11]) + int(fields[12]), private, cgroup)
    return procs


def groups(procs):
    """{root pid: [member pids]}: each process under the app it belongs to"""
    root_of = {}

    def root(pid):
        chain = []
        while pid in procs and pid not in root_of:
            chain.append(pid)
            parent = procs[pid][1]
            if parent not in procs or procs[parent][0] in SESSION:
                break
            pid = parent
        top = root_of.get(pid, pid)
        for p in chain:
            root_of[p] = top
        return top

    out = {}
    for pid in procs:
        out.setdefault(root(pid), []).append(pid)
    # Services under systemd (PipeWire, the portals, …) aren't apps
    return {r: m for r, m in out.items() if r in procs and not procs[r][4].endswith(".service")}


def unwrap(root, members, procs):
    """Past a wrapper script to the app it started (bash → steam), while it started just one thing"""
    for _ in range(4):
        if procs[root][0] not in WRAPPERS:
            break
        children = [p for p in members if procs[p][1] == root]
        if len(children) != 1:
            break
        root = children[0]
    return root


def app_id(unit):
    """app-flatpak-app.zen_browser.zen-123.scope → app.zen_browser.zen"""
    if not (unit.startswith("app-") and unit.endswith(".scope")):
        return ""
    name = unit[4:-6].rsplit("-", 1)[0]
    return name[8:] if name.startswith("flatpak-") else name


def main():
    before, before_t = scan(), time.monotonic()
    time.sleep(0.5)
    while True:
        now, now_t = scan(), time.monotonic()
        elapsed = max(0.1, now_t - before_t)
        apps = []
        for root, members in groups(now).items():
            pid = unwrap(root, members, now)
            if now[pid][0] in HIDDEN or now[root][0] in HIDDEN:
                continue
            ticks = sum(max(0, now[p][2] - before[p][2]) for p in members if p in before)
            apps.append({"name": now[pid][0], "appId": app_id(now[root][4]), "pid": pid,
                         "cpu": round(ticks / TICKS / elapsed / CPUS, 4),
                         "mem": sum(now[p][3] for p in members)})
        before, before_t = now, now_t
        top_cpu = sorted(apps, key=lambda a: -a["cpu"])[:ROWS]
        top_mem = sorted(apps, key=lambda a: -a["mem"])[:ROWS]
        print(json.dumps({"cpu": top_cpu, "mem": top_mem}), flush=True)
        time.sleep(INTERVAL)


if __name__ == "__main__":
    try:
        main()
    except (KeyboardInterrupt, BrokenPipeError):
        os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())  # No "broken pipe" on the way out
