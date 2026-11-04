#!/usr/bin/env python3
"""The whole library's captures, for the launcher's stats page: what Steam's F12 saved (every account's
userdata/<account>/760/remote/<appid>/screenshots) and the gameplay clips (<clips folder>/<game>/).

Usage: library_captures.py <clips folder> <clip thumbnail cache>
Prints one JSON object:
  {"shots", "shotBytes", "clips", "clipBytes", "latest": [{"kind": "shot"|"clip", "time", "image", "full",
   "appid" (shots) | "game" (clips: its folder's name, the game's name made safe)}]}
latest: the newest few of both, each with a small picture to show ("image": Steam's own thumbnail of a shot,
or the frame the Clips page made for a clip, list_clips.py's cache key; "" when there's none yet) and a big
one ("full": the shot itself, or that same frame).
"""
import glob, hashlib, json, os, sys

STEAM = os.path.expanduser("~/.local/share/Steam")
SHOTS = (".jpg", ".jpeg", ".png")
VIDEO = (".mp4", ".mkv", ".webm", ".mov")
LATEST = 5  # The stats page's Captures card: the newest large, four under it


def clip_thumb(path, st, cache):
    """list_clips.py's thumbnail for this clip, if it made one"""
    key = hashlib.sha1(f"{path}\0{st.st_size}\0{st.st_mtime_ns}".encode()).hexdigest()[:20]
    thumb = os.path.join(cache, key + ".jpg")
    return thumb if os.path.exists(thumb) else ""


def main():
    clips_root, cache = (sys.argv[1:3] + ["", ""])[:2]
    out = {"shots": 0, "shotBytes": 0, "clips": 0, "clipBytes": 0}
    found = []  # (time, kind, path, key, stat)
    for folder in glob.glob(os.path.join(STEAM, "userdata", "*", "760", "remote", "*", "screenshots")):
        appid = os.path.basename(os.path.dirname(folder))
        try:
            entries = list(os.scandir(folder))
        except OSError:
            continue
        for e in entries:  # Not into thumbnails/: Steam's small copies
            if e.name.lower().endswith(SHOTS) and e.is_file():
                st = e.stat()
                out["shots"] += 1
                out["shotBytes"] += st.st_size
                found.append((st.st_mtime, "shot", e.path, appid, st))
    if clips_root and os.path.isdir(clips_root):
        for game in os.scandir(clips_root):
            if not game.is_dir():
                continue
            for e in os.scandir(game.path):
                if e.name.lower().endswith(VIDEO) and e.is_file():
                    st = e.stat()
                    out["clips"] += 1
                    out["clipBytes"] += st.st_size
                    found.append((st.st_mtime, "clip", e.path, game.name, st))
    found.sort(key=lambda f: f[0], reverse=True)
    latest = []
    for time, kind, path, key, st in found[:LATEST]:
        if kind == "shot":
            thumb = os.path.join(os.path.dirname(path), "thumbnails", os.path.basename(path))
            latest.append({"kind": kind, "time": time, "image": thumb if os.path.exists(thumb) else path, "full": path, "appid": key})
        else:
            frame = clip_thumb(path, st, cache)
            latest.append({"kind": kind, "time": time, "image": frame, "full": frame, "game": key})
    out["latest"] = latest
    print(json.dumps(out))


if __name__ == "__main__":
    main()
