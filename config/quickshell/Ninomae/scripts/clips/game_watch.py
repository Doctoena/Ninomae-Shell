#!/usr/bin/env python3
"""Tells the shell which game is running, so the clip recorder only runs while you play.

Prints a line whenever it changes:
  steam <app id>      a Steam game (Steam runs each under `reaper SteamLaunch AppId=<id> -- …`)
  lutris <game name>  a Lutris game (under `lutris-wrapper <name> …`)
  custom <game id>    a game added by hand in the launcher (the launcher's custom_games.json, its
                      first argument): a Flatpak by its app scope, anything else by its program's name
  none                no game
  focus 1 / focus 0   whether the focused window is the game's own (for the crosshair): it belongs to the
                      game's processes (its launcher's process tree, or its Flatpak's sandbox), whatever
                      its size. Only printed while Hyprland's event socket can be read
It looks every second (reading /proc takes ~2 ms) and catches games however they were started: from the
launcher, Steam or Lutris. Focus follows Hyprland's events at once.
A game only counts once one of its windows has opened: Steam also runs a game's install scripts and shader
processing under its launch wrapper while it updates, and those have none. Without Hyprland it can't tell,
so a game counts from its first process.
"""
import json
import os
import select
import socket
import sys
import time

INTERVAL = 1.0
# Programs that start other things: by their name a game would always look running
GENERIC = {"sh", "bash", "dash", "zsh", "fish", "env", "python", "python3", "java", "wine", "wine64", "flatpak",
           "gamemoderun", "prime-run", "gtk-launch", "xdg-open", "steam", "lutris", "mangohud", "gamescope"}
SCOPES = f"/sys/fs/cgroup/user.slice/user-{os.getuid()}.slice/user@{os.getuid()}.service/app.slice"


class Custom:
    """The launcher's hand-added games, re-read when the file changes: {flatpak id: game id}, {program: game id}"""
    def __init__(self, path):
        self.path, self.mtime, self.flatpaks, self.programs = path, None, {}, {}

    def refresh(self):
        try:
            mtime = os.stat(self.path).st_mtime
        except OSError:
            self.flatpaks, self.programs = {}, {}
            return
        if mtime == self.mtime:
            return
        self.mtime, self.flatpaks, self.programs = mtime, {}, {}
        try:
            with open(self.path) as f:
                games = json.load(f)
        except (OSError, ValueError):
            return
        for g in games if isinstance(games, list) else []:
            gid, cmd = g.get("id", ""), g.get("command") or []
            if not gid.startswith("custom_"):
                continue
            if g.get("flatpakId"):
                self.flatpaks[g["flatpakId"]] = gid
            elif cmd and os.path.basename(cmd[0]) not in GENERIC:
                self.programs[os.path.basename(cmd[0]).encode()] = gid

    def running_flatpak(self):
        """(game id, Flatpak app id), or None. One listing, not a read per process: each Flatpak app runs in
        an app-flatpak-<id>-<n>.scope"""
        if not self.flatpaks:
            return None
        try:
            names = os.listdir(SCOPES)
        except OSError:
            return None
        for name in names:
            if name.startswith("app-flatpak-") and name.endswith(".scope"):
                app = name[len("app-flatpak-"):].rsplit("-", 1)[0]
                if app in self.flatpaks:
                    return self.flatpaks[app], app
        return None


def cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return f.read().split(b"\0")
    except OSError:  # Gone, or not ours
        return []


def find_game(custom):
    """(the line to print, a test for "this window's pid is the game's" or None, the Steam app id or "")"""
    lutris = None
    program = exe = None
    for entry in os.scandir("/proc"):
        if not entry.name.isdigit():
            continue
        argv = cmdline(entry.name)
        if not argv or not argv[0]:
            continue
        if b"SteamLaunch" in argv:
            for a in argv:
                if a.startswith(b"AppId="):
                    appid = a[6:].decode(errors="replace")
                    if appid.isdigit() and appid != "0":  # Steam first: Lutris can start Steam games too
                        return f"steam {appid}", under_steam(appid), appid
        if program is None and custom.programs:
            exe = os.path.basename(argv[0])
            program = custom.programs.get(exe)
        if lutris:
            continue
        head = argv[0].decode(errors="replace")
        if head.startswith("lutris-wrapper: "):  # Titled by setproctitle
            lutris = f"lutris {head[len('lutris-wrapper: '):].strip()}"
            continue
        # Else run by its interpreter: "python3 /usr/share/lutris/bin/lutris-wrapper <name> …"
        for i, a in enumerate(argv[:-1]):
            if a.endswith(b"/lutris-wrapper") or a == b"lutris-wrapper":
                lutris = f"lutris {argv[i + 1].decode(errors='replace')}"
                break
    if lutris:
        return lutris, under_lutris, ""
    flatpak = custom.running_flatpak()
    if flatpak:
        gid, app = flatpak
        return f"custom {gid}", in_flatpak(app), ""
    if program:
        return f"custom {program}", under_program(exe), ""
    return "none", None, ""


# Tests for "this pid is the game's": one of the processes its launcher started, or inside its sandbox
def under_steam(appid):
    tag = b"AppId=" + appid.encode()
    return lambda pid: any(b"SteamLaunch" in argv and tag in argv for argv in ancestry(pid))


def under_lutris(pid):
    return any(argv and (argv[0].startswith(b"lutris-wrapper") or any(a.endswith(b"lutris-wrapper") for a in argv))
               for argv in ancestry(pid))


def in_flatpak(app):
    return lambda pid: f"app-flatpak-{app}-" in read(f"/proc/{pid}/cgroup")


def under_program(exe):
    return lambda pid: any(argv and os.path.basename(argv[0]) == exe for argv in ancestry(pid))


def read(path):
    try:
        with open(path) as f:
            return f.read()
    except OSError:
        return ""


def ancestry(pid):
    """The argv of pid and each of its parents, up to init"""
    seen = 0
    while pid and pid > 1 and seen < 64:
        yield cmdline(pid)
        ppid = next((l.split()[1] for l in read(f"/proc/{pid}/status").splitlines() if l.startswith("PPid:")), "0")
        pid = int(ppid) if ppid.isdigit() else 0
        seen += 1


class Hyprland:
    """The focused window, from Hyprland's event socket (socket2) and its request socket"""
    def __init__(self):
        base = f"{os.environ.get('XDG_RUNTIME_DIR', '')}/hypr/{os.environ.get('HYPRLAND_INSTANCE_SIGNATURE', '')}"
        self.request_path = f"{base}/.socket.sock"
        self.events = None
        self.buf = b""
        self.opened = False  # A window opened since the last look (window_owned clears it)
        try:
            self.events = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            self.events.connect(f"{base}/.socket2.sock")
        except OSError:
            self.events = None

    def request(self, what):
        """Hyprland's JSON answer to a request, or None if it can't be asked"""
        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
                s.connect(self.request_path)
                s.sendall(b"j/" + what)
                data = b""
                while chunk := s.recv(65536):
                    data += chunk
            return json.loads(data)
        except (OSError, ValueError):
            return None

    def active(self):
        """(pid, class) of the focused window"""
        w = self.request(b"activewindow")
        return window(w) if isinstance(w, dict) else (0, "")

    def windows(self):
        """[(pid, class)] of every window, or None if Hyprland can't be asked"""
        ws = self.request(b"clients")
        return [window(w) for w in ws if isinstance(w, dict)] if isinstance(ws, list) else None

    def focus_changed(self):
        """Reads what's waiting; whether the focus moved"""
        try:
            chunk = self.events.recv(65536)
        except OSError:
            chunk = b""
        if not chunk:  # Hyprland went away
            self.events = None
            return False
        self.buf += chunk
        *lines, self.buf = self.buf.split(b"\n")
        self.opened |= any(l.startswith(b"openwindow>>") for l in lines)
        return any(l.startswith((b"activewindowv2>>", b"closewindow>>", b"openwindow>>")) for l in lines)


def window(w):
    return int(w.get("pid") or 0), w.get("class") or ""


def games_window(pid, cls, owns, appid):
    """Whether a window is the game's: one of its processes', or (no pid, as some X11 windows) Steam's
    steam_app_<id> class"""
    return (appid != "" and cls == f"steam_app_{appid}") or (pid > 0 and owns(pid))


def window_owned(hypr, owns, appid):
    """Whether the game has a window open (True when Hyprland can't say)"""
    hypr.opened = False
    windows = hypr.windows()
    return windows is None or any(games_window(pid, cls, owns, appid) for pid, cls in windows)


def main():
    custom = Custom(sys.argv[1] if len(sys.argv) > 1 else "")
    hypr = Hyprland()
    last, owns, appid, last_focus = None, None, "", None
    confirmed = None  # The game seen with a window: it counts until its processes end, windows or not
    waiting = None    # One seen without a window yet: looked at again when a window opens
    next_scan = 0.0
    while True:
        now = time.monotonic()
        changed = False
        if now >= next_scan:
            custom.refresh()
            current, owns, appid = find_game(custom)
            if current == "none":
                confirmed = waiting = None
            elif current != confirmed:
                # Without the event socket there's no "a window opened", so it looks every time
                if (current != waiting or hypr.opened or hypr.events is None) and window_owned(hypr, owns, appid):
                    confirmed, waiting = current, None
                else:  # Only its updater, installer or shader job so far
                    waiting = current
                    current, owns, appid = "none", None, ""
            if current != last:
                print(current, flush=True)
                last, changed = current, True
            next_scan = now + INTERVAL
        if hypr.events is not None:
            ready, _, _ = select.select([hypr.events], [], [], max(0.0, next_scan - time.monotonic()))
            if ready and hypr.focus_changed():
                changed = True
            if changed or last_focus is None:
                focus = False
                if owns is not None:  # Only asked while a game runs: no request per focus change otherwise
                    focus = games_window(*hypr.active(), owns, appid)
                if focus != last_focus:
                    print(f"focus {1 if focus else 0}", flush=True)
                    last_focus = focus
        else:
            time.sleep(max(0.0, next_scan - time.monotonic()))


if __name__ == "__main__":
    try:
        main()
    except (KeyboardInterrupt, BrokenPipeError):
        sys.exit(0)
