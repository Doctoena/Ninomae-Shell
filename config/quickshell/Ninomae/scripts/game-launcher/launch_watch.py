#!/usr/bin/env python3
"""Follows a game from the moment it's launched until its window shows, for the launch drawer
(modules/gameLauncher/LaunchSplash.qml). Prints one JSON object per line whenever something changes:

  {"stage": <stage>, "progress": <0–1, or -1 when there's no number>, "error": <Steam's error or "">}

Stages, in the order a launch usually goes through them:
  preparing   Steam's checks before anything else (licence, stats, cloud/controller config)
  updating    downloading an update first (progress from the game's appmanifest and downloading/ folder)
  setup       the game's first-time install script (redistributables)
  cloud       syncing cloud saves
  shaders     processing the Vulkan shader cache (progress from shader_log.txt)
  choose      Steam is asking which launch option to use
  starting    the process is up, waiting for its first window
  window      one of the game's windows opened; the script exits
  exited      the game quit before it showed a window; the script exits
  failed      Steam couldn't launch it ("error" is e.g. "AppError_19"); the script exits
  timeout     nothing settled in 10 minutes; the script exits

Usage: launch_watch.py steam <app id> <appmanifest path or "">
       launch_watch.py lutris <game name>
Steam's stages come from its console_log.txt ("LaunchApp changed task to …"). Lutris games only get
"starting" and the end states. A window counts as the game's when its process descends from the
game's root process: `reaper SteamLaunch AppId=<id>` for Steam, `lutris-wrapper <name>` for Lutris
(the same ones watch_game.py looks for), so Steam's own dialogs and anything else never count.
Windows are only looked up when Hyprland reports one opening (its event socket), plus once when the
game's process first shows up, in case its window was already open.
"""
import json
import os
import re
import select
import socket
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  # Run with -I, which leaves its own folder out
from watch_game import matches  # noqa: E402

LOGS = os.path.expanduser("~/.local/share/Steam/logs")
POLL = 0.25
TIMEOUT = 600
# Steam's launch tasks → stage. Anything not listed keeps the current stage
TASKS = {
    "CheckShaderDepotManifest": "preparing", "UpdatingAppInfo": "preparing", "RequestingLicense": "preparing",
    "SiteLicenseSeatCheckout": "preparing", "SynchronizingStats": "preparing", "UnlockingH264": "preparing",
    "SynchronizingControllerConfig": "preparing", "ShowInterstitials": "preparing",
    "DownloadingDepots": "updating",
    "RunningInstallScript": "setup", "ProcessingInstallScript": "setup",
    "SynchronizingCloud": "cloud",
    "ProcessingShaderCache": "shaders",
    "ShowLaunchOption": "choose",
    "DelayLaunch": "starting", "CreatingProcess": "starting", "WaitingGameWindow": "starting", "Completed": "starting",
    "Failed": "failed",
}


class Follower:
    """New lines of a log as it grows, from a little before the launch (Steam may already have
    written the first ones). Starts over when Steam rotates the file."""
    def __init__(self, path, since):
        self.path, self.since, self.pos = path, since, 0
        try:
            self.pos = max(0, os.path.getsize(path) - 32768)
        except OSError:
            pass
        self.backlog = True

    def lines(self):
        try:
            if os.path.getsize(self.path) < self.pos:
                self.pos = 0
            with open(self.path, errors="replace") as f:
                f.seek(self.pos)
                text = f.read()
                self.pos = f.tell()
        except OSError:
            return []
        lines = text.splitlines()
        if self.backlog:  # From the tail read at the start, only what's from this launch
            self.backlog = False
            lines = [l for l in lines if logged_at(l) >= self.since]
        return lines


def logged_at(line):
    try:
        return time.mktime(time.strptime(line[1:20], "%Y-%m-%d %H:%M:%S"))
    except ValueError:
        return 0


def manifest_progress(path):
    try:
        with open(path) as f:
            text = f.read()
    except OSError:
        return -1
    num = lambda key: int((re.search(rf'"{key}"\s+"(\d+)"', text) or [0, 0])[1])
    total = num("BytesToDownload") + num("BytesToStage")
    progress = (num("BytesDownloaded") + num("BytesStaged")) / total if total > 0 else -1
    # Steam only rewrites those counts on state changes: the live part is what's been written to
    # steamapps/downloading/<id>, or workshop/downloads/<id> for its mods (allocated bytes, Steam
    # writes the files sparsely)
    to_stage = num("BytesToStage") or num("BytesToDownload")
    m = re.search(r"appmanifest_(\d+)\.acf$", path)
    if to_stage > 0 and m:
        steamapps = os.path.dirname(path)
        staged = 0
        for folder in (os.path.join(steamapps, "downloading", m[1]), os.path.join(steamapps, "workshop", "downloads", m[1])):
            for parent, _, files in os.walk(folder):
                for name in files:
                    try:
                        staged += os.lstat(os.path.join(parent, name)).st_blocks * 512
                    except OSError:
                        pass
        progress = max(progress, min(1, staged / to_stage))
    return progress


def hyprland_events():
    """Hyprland's event socket, or None (then windows are checked on every process check instead)."""
    try:
        path = os.path.join(os.environ["XDG_RUNTIME_DIR"], "hypr", os.environ["HYPRLAND_INSTANCE_SIGNATURE"], ".socket2.sock")
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.connect(path)
        sock.setblocking(False)
        return sock
    except (KeyError, OSError):
        return None


def window_opened(sock):
    """Whether any of the events waiting on the socket is a window opening."""
    try:
        data = sock.recv(65536).decode(errors="replace")
    except BlockingIOError:
        return False
    return "openwindow>>" in data


def alive(pids):
    return {p for p in pids if os.path.exists(f"/proc/{p}")}


def root_pids(kind, key):
    found = set()
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                argv = f.read().decode(errors="replace").split("\0")[:-1]
        except OSError:
            continue
        if matches(argv, kind, key):
            found.add(int(pid))
    return found


def parent(pid):
    try:
        with open(f"/proc/{pid}/stat") as f:
            return int(f.read().rsplit(")", 1)[1].split()[1])  # After the name, which may hold spaces
    except (OSError, IndexError, ValueError):
        return 0


def game_window(roots):
    """Whether any window belongs to a process under one of the game's root processes."""
    try:
        clients = json.loads(subprocess.run(["hyprctl", "clients", "-j"], capture_output=True, text=True, timeout=2).stdout)
    except Exception:
        return False
    for c in clients:
        pid = c.get("pid", 0)
        for _ in range(40):
            if pid in roots:
                return True
            if pid <= 1:
                break
            pid = parent(pid)
    return False


def main():
    kind, key = sys.argv[1], sys.argv[2]
    manifest = sys.argv[3] if len(sys.argv) > 3 else ""
    started = time.time()
    state = {"stage": "preparing" if kind == "steam" else "starting", "progress": -1, "error": ""}
    last = None

    def emit(**changes):
        nonlocal last
        state.update(changes)
        out = json.dumps(state)
        if out != last:
            print(out, flush=True)
            last = out

    emit()
    console = Follower(os.path.join(LOGS, "console_log.txt"), started - 3) if kind == "steam" else None
    shaders = Follower(os.path.join(LOGS, "shader_log.txt"), started - 3) if kind == "steam" else None
    task_re = re.compile(rf"GameAction \[AppID {re.escape(key)}, ActionID \d+\] : LaunchApp (?:changed task to (\w+)|failed with (\w+))")
    replay_re = re.compile(rf"Still replaying {re.escape(key)} \((\d+)%")
    events = hyprland_events()
    roots, seen_roots, last_process_check, check_windows = set(), False, 0, False
    last_progress_check = 0

    while time.time() - started < TIMEOUT:
        # Sleeps until a Hyprland event or the next poll
        if events and select.select([events], [], [], POLL)[0]:
            check_windows |= window_opened(events)
        elif not events:
            time.sleep(POLL)

        if console:
            for line in console.lines():
                m = task_re.search(line)
                if not m:
                    continue
                if m[2]:
                    emit(stage="failed", error=m[2])
                    return
                stage = TASKS.get(m[1])
                if stage == "failed":
                    emit(stage="failed")
                    return
                if stage == "preparing" and state["stage"] != "preparing":
                    continue  # Steam's small checks between the real steps: keep showing the last real one
                if stage and stage != state["stage"]:
                    emit(stage=stage, progress=-1)
            for line in shaders.lines():
                m = replay_re.search(line)
                if m and state["stage"] == "shaders":
                    emit(progress=int(m[1]) / 100)
            if state["stage"] == "updating" and manifest and time.time() - last_progress_check >= 1:
                last_progress_check = time.time()  # Walks the download folder: once a second is plenty
                p = manifest_progress(manifest)
                if p >= 0:  # Never steps back (Steam moves finished files out while it commits)
                    emit(progress=round(max(p, state["progress"]), 2))

        now = time.time()
        if now - last_process_check >= 0.5:  # Twice a second is plenty
            last_process_check = now
            # Once found, the root process only needs to be checked on, not searched for again
            roots = alive(roots) or root_pids(kind, key)
            if roots and not seen_roots:
                seen_roots = check_windows = True  # Its window may already be open
                if state["stage"] in ("preparing", "updating", "setup", "cloud", "shaders", "choose"):
                    emit(stage="starting", progress=-1)  # Steam didn't log it (or Lutris): it's up
            elif not roots and seen_roots:
                emit(stage="exited", progress=-1)
                return
        if roots and (check_windows or not events):
            check_windows = False
            if game_window(roots):
                emit(stage="window", progress=-1)
                return
    emit(stage="timeout", progress=-1)


if __name__ == "__main__":
    try:
        main()
    except (BrokenPipeError, KeyboardInterrupt):
        pass
