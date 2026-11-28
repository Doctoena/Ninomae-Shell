#!/usr/bin/env python3
"""Pauses and resumes Steam's downloads, through the same calls as the buttons in Steam's Downloads page.

  steam_control.py resume <appid>     → starts it now, ahead of the rest (Steam's "Move to top"); also the retry
  steam_control.py remove <appid>     → takes it off the download queue (Steam's ✕); it updates later, or when played
  steam_control.py remove-and-resume <appid>
                                      → the same for the paused one at the queue's head: the rest go again
  steam_control.py pause-all | resume-all
  steam_control.py skip-shaders <appid> → a launch waiting on Vulkan shader processing starts now (Steam's Skip)
  steam_control.py status             → on (Steam runs with the plugin), outdated (Steam runs an older copy
                                        than the one on disk: a restart loads it), installed (Steam isn't
                                        running, or only just started), unreachable (Steam has run a while
                                        but the plugin doesn't answer) or missing

The calls run inside Steam, in the shell's Millennium plugin (themes/steam/ninomae-plugin). The two talk
through a mailbox in ~/.cache/ninomae-steam (in home: Steam's runtime container has a /run/user of its own).
A request is a file in requests/, the plugin answers in replies/ and keeps "alive" ("<now> <loaded>") up to
date while Steam runs. The plugin checks every 2 s, and every 0.15 s while "wanted" is fresh: the launcher's
downloads feed (steam_downloads.py) touches it while it's open, and so does each request.
Errors (JSON "error"): off (Steam or the plugin isn't running), failed (Steam refused the call, as when Valve
renames it, or didn't answer in time; "detail" says what Steam said).
"""
import json, os, subprocess, sys, time, uuid

MAILBOX = os.path.expanduser("~/.cache/ninomae-steam")  # The plugin's path too: not XDG_CACHE_HOME, set differently in Steam
ALIVE_SECS = 5  # The plugin writes "alive" every second while Steam runs: older than this, it's gone
STARTUP_SECS = 30  # Steam up this long and still no "alive": the plugin isn't coming
PLUGIN = os.path.join(os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share"), "millennium", "plugins", "ninomae")
PLUGIN_FILES = ("backend/main.lua", ".millennium/Dist/index.js", "plugin.json")
MILLENNIUM_CONFIG = os.path.expanduser("~/.config/millennium/config.json")


def _alive():
    """When the running plugin was loaded, or None if Steam isn't running with it"""
    try:
        path = os.path.join(MAILBOX, "alive")
        if time.time() - os.path.getmtime(path) >= ALIVE_SECS:
            return None
        with open(path, encoding="utf-8") as f:
            parts = f.read().split()
        return int(parts[1]) if len(parts) > 1 else 0
    except (OSError, ValueError):
        return None


def available():
    """Steam is running with the plugin, which looks at the mailbox every moment"""
    return _alive() is not None


def outdated(loaded):
    """The plugin's files changed after Steam loaded them (an update): Steam runs the older copy"""
    try:
        return any(os.path.getmtime(os.path.join(PLUGIN, f)) > loaded + 1 for f in PLUGIN_FILES)
    except OSError:
        return False


def want():
    """Asks the plugin for quick checks for the next few seconds (it slows down again on its own)"""
    try:
        with open(os.path.join(MAILBOX, "wanted"), "a"):
            pass
        os.utime(os.path.join(MAILBOX, "wanted"))
    except OSError:
        pass


def installed():
    """The plugin is in Millennium's plugins folder, and turned on there"""
    if not os.path.isdir(PLUGIN):
        return False
    try:
        with open(MILLENNIUM_CONFIG, encoding="utf-8") as f:
            return "ninomae" in json.load(f).get("plugins", {}).get("enabledPlugins", [])
    except (OSError, ValueError, AttributeError):
        return False


def _steam_up_for():
    """Seconds since Steam started (its oldest process), or None if it isn't running"""
    out = subprocess.run(["ps", "-C", "steam", "-o", "etimes="], capture_output=True, text=True).stdout.split()
    return max(map(int, out)) if out else None


def status():
    """on, outdated, installed, unreachable or missing (see the top)"""
    if not installed():
        return "missing"
    loaded = _alive()
    if loaded is not None:
        return "outdated" if outdated(loaded) else "on"
    up = _steam_up_for()
    return "unreachable" if up is not None and up >= STARTUP_SECS else "installed"


def request(cmd, timeout=6, **args):
    """Runs one of the plugin's commands in Steam: (its value, None), or (None, error). The error is
    "off", "failed", or "failed: <what Steam said>"
    """
    if not available():
        return None, "off"
    want()
    rid = uuid.uuid4().hex
    req = os.path.join(MAILBOX, "requests", rid + ".json")
    rep = os.path.join(MAILBOX, "replies", rid + ".json")
    try:
        with open(req + ".tmp", "w", encoding="utf-8") as f:  # Whole, or not at all: the plugin only reads *.json
            json.dump({"cmd": cmd, "args": args}, f)
        os.rename(req + ".tmp", req)
    except OSError:
        return None, "off"
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        try:
            with open(rep, encoding="utf-8") as f:
                reply = json.load(f)
            os.remove(rep)
            break
        except FileNotFoundError:
            time.sleep(0.03)
        except (OSError, ValueError):
            return None, "failed"
    else:
        for leftover in (req, rep):  # Not taken in time: it isn't run later, when it would surprise you
            try: os.remove(leftover)
            except OSError: pass
        return None, "failed"
    return (reply.get("value"), None) if reply.get("ok") else (None, f"failed: {reply.get('error') or 'unknown'}")


def main():
    a = sys.argv[1:]
    if a == ["status"]:
        print(status())
        return 0
    if len(a) == 2 and a[0] == "resume" and a[1].isdigit():
        value, err = request("resume", appid=int(a[1]))
    elif len(a) == 2 and a[0] in ("remove", "remove-and-resume") and a[1].isdigit():
        value, err = request("remove", appid=int(a[1]), resumeAll=a[0] == "remove-and-resume")
    elif len(a) == 2 and a[0] == "skip-shaders" and a[1].isdigit():
        value, err = request("skipShaders", appid=int(a[1]))
    elif a in (["pause-all"], ["resume-all"]):
        value, err = request("enableAll", on=a[0] == "resume-all")
    else:
        print(__doc__)
        return 1
    ok = value is True
    err = err or (None if ok else "failed")
    code, _, detail = (err or "").partition(": ")
    print(json.dumps({"ok": ok, "error": code or None, **({"detail": detail} if detail else {})}))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
