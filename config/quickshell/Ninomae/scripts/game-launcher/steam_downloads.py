#!/usr/bin/env python3
"""Steam's downloads right now, for the game launcher's Downloads panel, without Steam's window.

  steam_downloads.py           → one JSON line (below), then exits
  steam_downloads.py --watch   → a JSON line now and on every change, following Steam as it goes (the
                                 launcher runs this while it's open). Ends when its output is closed

Steam rewrites a game's appmanifest only when its state changes, so the live part comes from its
content log (logs/content_log.txt), which records every state change ("AppID 1422450 state changed :
Update Required,Update Queued,Update Running,"), why a download stopped, and the rate about once a
minute; and from the download folder filling up, measured every couple of seconds for the speed.

  {"steamRunning", "remoteControl" (pause and resume work: Steam's debugging port answers),
   "gameRunning" (a Steam game is open: Steam holds downloads), "queuePaused" (every download paused),
   "rate" (bytes a second, -1 when nothing downloads), "history" (recent rates, oldest first),
   "items": [...], "finished": [...]}
  items     what's downloading, queued, paused or waiting, in Steam's order (the one downloading first):
            {"appid", "name", "state", "since" (when Steam logged that state, 0 if it didn't), "progress",
             "toDownload", "eta", "installing", "delayUntil", "error"}
            state: downloading | queued | paused (by you) | error (Steam stopped it: "error" says why, as
            "Missing update files"; resuming retries it) | suspended (held: a game is running, or every
            download is paused) | scheduled (Steam starts it at delayUntil) | waiting (an update that
            starts when you play it) | stopped (Steam isn't running)
  finished  installs and updates done in the last day, newest first: {"appid", "name", "at"}
"""
import glob, json, os, re, socket, subprocess, sys, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  # Run with -I, which leaves its own folder out
from launch_watch import manifest_progress  # noqa: E402

STEAM = os.path.expanduser("~/.local/share/Steam")
LOG = os.path.join(STEAM, "logs", "content_log.txt")
READ_BYTES = 1 << 20  # The last MB of the log to start from: days of state changes, without reading all of it

LINE = re.compile(r"^\[(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)\] (.*)$")
STATE = re.compile(r"^AppID (\d+) state changed : (.*)$")
FINISHED = re.compile(r"^AppID (\d+) scheduler finished : removed from schedule \(result No Error")
RATE = re.compile(r"^Current download rate: ([\d.]+) Mbps")
SESSION = re.compile(r"^Client version: ")  # Written each time Steam starts
DELAY = re.compile(r"\(Update delayed for (\d+) secs\)")
CANCELED = re.compile(r"^AppID (\d+) update canceled : .*\(([^()]+)\)\s*$")  # "… (Missing update files)"
ACTIVE = ("Update Required", "Update Queued", "Update Running", "Update Started", "Update Paused")
ORDER = ["downloading", "queued", "error", "suspended", "paused", "scheduled", "waiting", "stopped"]


_libraries = (None, {STEAM})  # (libraryfolders.vdf's mtime, its libraries)


def libraries():
    """Steam's library folders, read again only when libraryfolders.vdf changes"""
    global _libraries
    path = os.path.join(STEAM, "steamapps", "libraryfolders.vdf")
    try:
        mtime = os.path.getmtime(path)
        if mtime != _libraries[0]:
            text = open(path, encoding="utf-8").read()
            _libraries = (mtime, {STEAM, *re.findall(r'"path"\s+"([^"]+)"', text)})
    except OSError:
        pass
    return _libraries[1]


def field(text, key):
    m = re.search(rf'"{key}"\s+"([^"]*)"', text)
    return m[1] if m else ""


def port_open(port=8080):
    try:
        socket.create_connection(("127.0.0.1", port), timeout=0.3).close()
        return True
    except OSError:
        return False


def running(pattern, exact=False):
    return subprocess.run(["pgrep", "-x" if exact else "-f", pattern], capture_output=True).returncode == 0


class Log:
    """Steam's content log, read once from its last MB and then followed as it grows"""

    def __init__(self):
        self.latest, self.finished, self.downloaded, self.errors = {}, {}, set(), {}
        self.rate = None  # (time, bytes a second), as Steam last logged it
        self.pos, self.partial = None, b""

    def update(self):
        """Reads what's new; True if anything was"""
        try:
            size = os.path.getsize(LOG)
        except OSError:
            return False
        if self.pos is None or size < self.pos:  # First read, or Steam started a new log
            if self.pos is not None:
                self.__init__()
            self.pos = max(0, size - READ_BYTES)
        if size == self.pos:
            return False
        with open(LOG, "rb") as f:
            f.seek(self.pos)
            data = self.partial + f.read(size - self.pos)
        self.pos = size
        *lines, self.partial = data.split(b"\n")
        for line in lines:
            self._line(line.decode(errors="replace"))
        return True

    def _line(self, line):
        m = LINE.match(line)
        if not m:
            return
        msg = m[2]
        if SESSION.match(msg):
            self.latest.clear()  # An older state can be a leftover Steam never cleared
            return
        s = STATE.match(msg)
        c = None if s else CANCELED.match(msg)
        f = None if s or c else FINISHED.match(msg)
        r = None if s or c or f else RATE.match(msg)
        if not (s or c or f or r):
            return  # Most lines (write gaps, depots…): no need for the time
        try:
            at = time.mktime(time.strptime(m[1], "%Y-%m-%d %H:%M:%S"))
        except ValueError:
            return
        if s:
            appid, rest = s[1], s[2]
            states = {p.strip() for p in rest.split(",")}
            if "Update Running" in states:
                self.downloaded.add(appid)
                self.errors.pop(appid, None)  # Going again: whatever stopped it is over
            self.latest[appid] = (at, states, rest, self.errors.get(appid, ""))
        elif c:
            if c[2] not in ("Suspended", "Canceled"):  # Held by Steam, or stopped by you: not errors
                self.errors[c[1]] = c[2]
        elif f:
            if f[1] in self.downloaded:  # Only real downloads: a check that found nothing finishes too
                self.finished[f[1]] = at
                self.downloaded.discard(f[1])
        else:
            self.rate = (at, float(r[1]) * 1e6 / 8)


class Downloads:
    def __init__(self):
        self.log = Log()
        self.progress = {}  # appid → (key it was measured for, progress): measured again when the key changes
        self.speed = {}  # appid → (time, progress) last measured, for the live rate
        self.rate, self.history = -1.0, []
        self.manifests = {}  # path → (mtime, name, StateFlags, BytesToDownload): read again when it changes
        self.checked = 0  # When Steam's processes were last looked at
        self.steam = self.port = self.game = False

    def _progress(self, appid, path, state, mtime, live):
        """How far it is: measured again when it changes state or Steam rewrites its manifest, and every
        couple of seconds (live) while it downloads, since the download folder is what grows then"""
        key = (state, mtime, int(time.time() / 2) if live else 0)
        cached = self.progress.get(appid)
        if cached and cached[0] == key:
            return cached[1]
        value = manifest_progress(path)
        if cached and cached[0][0] == state:
            value = max(value, cached[1])  # Never back: Steam moves finished files out while it commits
        self.progress[appid] = (key, value)
        return value

    def _manifest(self, path):
        """(mtime, name, StateFlags, BytesToDownload) of an appmanifest, or None if it's gone"""
        try:
            mtime = os.path.getmtime(path)
            cached = self.manifests.get(path)
            if cached and cached[0] == mtime:
                return cached
            text = open(path, encoding="utf-8", errors="replace").read()
        except OSError:
            return None
        appid = re.search(r"(\d+)\.acf$", path)[1]
        info = (mtime, field(text, "name") or appid, int(field(text, "StateFlags") or 0), int(field(text, "BytesToDownload") or 0))
        self.manifests[path] = info
        return info

    def snapshot(self):
        now = time.time()
        self.log.update()
        if now - self.checked >= 4:  # Processes: a few seconds out is fine
            self.checked = now
            self.steam = running("steam", exact=True)
            self.port = self.steam and port_open()
            self.game = self.steam and running("SteamLaunch AppId=")
        items, current, names = [], None, {}
        for lib in libraries():
            for path in glob.glob(os.path.join(lib, "steamapps", "appmanifest_*.acf")):
                appid = re.search(r"(\d+)\.acf$", path)[1]
                info = self._manifest(path)
                if not info:
                    continue
                mtime, names[appid], flags, to_download = info
                entry = self.log.latest.get(appid)
                error, since = "", 0
                if entry and any(a in entry[1] for a in ACTIVE):
                    at, states, rest, error = entry
                    delay = DELAY.search(rest)
                    if not self.steam: state = "stopped"
                    elif "Update Paused" in states: state = "error" if error else "paused"
                    elif "(Suspended)" in rest: state = "suspended"
                    elif "Update Running" in states: state = "downloading"
                    elif delay: state = "scheduled"
                    elif "Update Queued" in states: state = "queued"
                    else: state = "waiting"
                    delay_until = at + int(delay[1]) if delay else 0
                    since = at
                elif not entry and flags & (2 | 512):  # Not in the log since Steam started: the manifest's word
                    state = "stopped" if not self.steam else "paused" if flags & 512 else "waiting"
                    delay_until = 0
                else:
                    continue
                progress = self._progress(appid, path, state, mtime, state == "downloading") if state != "waiting" else -1
                item = {
                    "appid": appid, "name": names[appid], "state": state, "since": since,
                    "progress": round(progress, 4) if progress >= 0 else -1,
                    "toDownload": to_download,
                    "installing": not flags & 4, "delayUntil": delay_until,
                    "error": error if state == "error" else "", "eta": -1,
                }
                items.append(item)
                if state == "downloading" and current is None:
                    current = item
        items.sort(key=lambda i: (ORDER.index(i["state"]), i["delayUntil"], i["name"].lower()))
        self._measure(current, now)
        if current and self.rate > 0 and current["toDownload"] > 0 and current["progress"] >= 0:
            current["eta"] = round(current["toDownload"] * (1 - current["progress"]) / self.rate)
        done = sorted(((a, t) for a, t in self.log.finished.items() if now - t < 86400 and a in names
                       and not any(i["appid"] == a for i in items)), key=lambda x: -x[1])[:8]
        return {
            "steamRunning": self.steam,
            "remoteControl": self.port,
            "gameRunning": self.game,
            "queuePaused": any(i["state"] == "suspended" for i in items) and not self.game and current is None,
            "rate": round(self.rate) if current and self.rate > 0 else -1,
            "history": [round(r) for r in self.history] if current else [],
            "items": items,
            "finished": [{"appid": a, "name": names[a], "at": t} for a, t in done],
        }

    def _measure(self, current, now):
        """The live rate: how fast the download's progress moves, as network bytes (the folder fills with
        uncompressed data: progress times the download's size is what came over the network). Smoothed,
        a sample each time it's measured for the panel's graph. Steam's own logged rate until then"""
        if not current:
            self.speed.clear()
            self.rate, self.history = -1.0, []
            return
        appid, progress = current["appid"], current["progress"]
        last = self.speed.get(appid)
        if last is None:
            self.speed = {appid: (now, progress)}
            self.history = []
            logged = self.log.rate
            self.rate = logged[1] if logged and now - logged[0] < 120 else -1.0
            return
        if now - last[0] >= 2 and progress > last[1] or now - last[0] >= 6:
            measured = max(0.0, (progress - last[1]) * current["toDownload"] / (now - last[0]))
            self.rate = measured if self.rate < 0 else self.rate * 0.6 + measured * 0.4
            self.speed[appid] = (now, progress)
            self.history = (self.history + [self.rate])[-30:]


def main():
    downloads = Downloads()
    if sys.argv[1:] != ["--watch"]:
        print(json.dumps(downloads.snapshot()))
        return
    last = None
    while True:
        snap = downloads.snapshot()
        out = json.dumps(snap)
        if out != last:
            print(out, flush=True)
            last = out
        time.sleep(1 if snap["rate"] > 0 or any(i["state"] == "downloading" for i in snap["items"]) else 2)


if __name__ == "__main__":
    try:
        main()
    except (BrokenPipeError, KeyboardInterrupt):
        pass
